import Foundation
@preconcurrency import WebKit

enum CloudWebInputError: LocalizedError {
    case unavailable, invalidCoordinates, timedOut, mainThread, pageFailure(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "云原神页面或输入 SDK 尚未就绪。"
        case .invalidCoordinates: "云原神输入坐标不在视频区域内。"
        case .timedOut: "云原神网页输入确认超时，自动化已暂停。"
        case .mainThread: "网页输入必须通过 Core 的异步输入队列执行。"
        case .pageFailure(let error): "云原神网页输入失败：\(error)"
        }
    }
}

/// Synchronous Core callbacks wait off the main thread; WebKit always runs on the main actor.
/// Page epochs and deadlines also cancel queued/in-flight holds after navigation or stop.
final class WKWebInputBridge: @unchecked Sendable {
    private final class Reply: @unchecked Sendable {
        let condition = NSCondition()
        private var result: Result<String, Error>?
        func finish(_ value: Result<String, Error>) {
            condition.lock(); defer { condition.unlock() }
            guard result == nil else { return }
            result = value; condition.broadcast()
        }
        func wait(until deadline: Date) throws -> String {
            condition.lock(); defer { condition.unlock() }
            while result == nil {
                if !condition.wait(until: deadline) { throw CloudWebInputError.timedOut }
            }
            return try result!.get()
        }
    }

    @MainActor private weak var webView: WKWebView?
    @MainActor private var epoch: String?
    @MainActor private var generation: UInt64 = 0
    @MainActor private var pending: [UUID: Reply] = [:]
    @MainActor var canDispatch: (() -> Bool)?
    @MainActor var onFailure: ((String) -> Void)?

    @MainActor init(webView: WKWebView) { self.webView = webView }

    @MainActor final class PageReply {
        private var continuation: CheckedContinuation<Bool, Error>?
        init(_ continuation: CheckedContinuation<Bool, Error>) { self.continuation = continuation }
        func finish(_ result: Result<Bool, Error>) {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    // WebKit cancellation does not necessarily complete a hung JavaScript promise.
    // A one-shot callback race bounds the native lifecycle without waiting on that promise.
    @MainActor static func pageReply(timeout: TimeInterval = 3, submit: (PageReply) -> Void) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            let reply = PageReply(continuation)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                reply.finish(.failure(CloudWebInputError.timedOut))
            }
            submit(reply)
        }
    }

    @MainActor private func submitBoolean(_ source: String, arguments: [String: Any], reply: PageReply) {
        guard let view = webView else { reply.finish(.failure(CloudWebInputError.unavailable)); return }
        view.callAsyncJavaScript(source, arguments: arguments, in: nil, in: .page,
            completionHandler: { result in
                switch result {
                case .success(let value): reply.finish(.success(value as? Bool == true))
                case .failure(let error): reply.finish(.failure(error))
                }
            })
    }

    @MainActor func beginSession() async throws {
        guard let view = webView, Self.isGameOrigin(view.url), canDispatch?() == true else { throw CloudWebInputError.unavailable }
        suspend()
        let next = UUID().uuidString
        let currentGeneration = generation
        let success = try await Self.pageReply { reply in
            self.submitBoolean("""
                if (Date.now() >= deadline) throw new Error('input session startup expired');
                const sdk = window.__ysInputInject;
                if (!sdk) throw new Error('Web SDK unavailable');
                sdk.releaseAll();
                const s = sdk.status();
                if (s.pressedKeys.length || s.pressedButtons.length || s.rtcDataChannelState !== 'open' || !s.gameDataStarted)
                    throw new Error('Web SDK input session not ready');
                window.__bgiMacInputEpoch = next;
                return true;
                """, arguments: ["next": next, "deadline": Date().addingTimeInterval(3).timeIntervalSince1970 * 1000], reply: reply)
        }
        guard success, generation == currentGeneration, Self.isGameOrigin(view.url), canDispatch?() == true else {
            throw CloudWebInputError.unavailable
        }
        epoch = next
    }

    @MainActor func suspend() {
        generation &+= 1
        epoch = nil
        let replies = Array(pending.values); pending.removeAll()
        replies.forEach { $0.finish(.failure(CloudWebInputError.unavailable)) }
        // Invalidate before releasing: old delayed presses cannot release a newer session's keys.
        webView?.evaluateJavaScript("window.__bgiMacInputEpoch = null; window.__ysInputInject?.releaseAll()")
    }

    @MainActor @discardableResult func releaseAndSuspend() async -> Bool {
        suspend()
        guard let view = webView, Self.isGameOrigin(view.url) else { return false }
        do {
            return try await Self.pageReply { reply in
                self.submitBoolean("""
                    if (Date.now() >= deadline) throw new Error('owned input release expired');
                    const sdk = window.__ysInputInject;
                    if (!sdk) return false;
                    sdk.releaseAll();
                    const s = sdk.status();
                    return !s.pressedKeys.length && !s.pressedButtons.length;
                    """, arguments: ["deadline": Date().addingTimeInterval(3).timeIntervalSince1970 * 1000], reply: reply)
            }
        } catch { return false }
    }

    func execute(_ commands: [[String: Any]], timeout: TimeInterval = 8) throws -> [String: Any] {
        guard !Thread.isMainThread else { throw CloudWebInputError.mainThread }
        let json = String(data: try JSONSerialization.data(withJSONObject: commands), encoding: .utf8)!
        let releaseOnly = commands.count == 1 && commands[0]["method"] as? String == "releaseAll"
        let deadline = Date().addingTimeInterval(timeout)
        let reply = Reply()
        let id = UUID()
        Task { @MainActor [weak self] in
                guard let self, let view = self.webView, self.epoch != nil || releaseOnly,
                      Self.isGameOrigin(view.url), Date() < deadline,
                      releaseOnly || self.canDispatch?() == true else {
                    reply.finish(.failure(CloudWebInputError.unavailable)); return
                }
                let epoch = self.epoch ?? ""
                self.pending[id] = reply
                do {
                    let value = try await view.callAsyncJavaScript(Self.executionScript,
                        arguments: ["commandsJSON": json, "epoch": epoch,
                                    "deadline": deadline.timeIntervalSince1970 * 1000],
                        in: nil, contentWorld: .page)
                    self.pending.removeValue(forKey: id)
                    guard (self.epoch ?? "") == epoch else { reply.finish(.failure(CloudWebInputError.unavailable)); return }
                    guard let text = value as? String else { throw CloudWebInputError.unavailable }
                    reply.finish(.success(text))
                } catch {
                    self.pending.removeValue(forKey: id)
                    reply.finish(.failure(error))
                    guard (self.epoch ?? "") == epoch else { return }
                    self.suspend(); self.onFailure?(error.localizedDescription)
                }
        }
        do {
            let result = try reply.wait(until: deadline)
            return try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] ?? [:]
        } catch {
            Task { @MainActor [weak self] in
                guard let self, self.pending.removeValue(forKey: id) != nil else { return }
                self.suspend(); self.onFailure?(error.localizedDescription)
            }
            throw error
        }
    }

    static func isGameOrigin(_ url: URL?) -> Bool {
        url?.scheme == "https" && url?.host == "ys.mihoyo.com" && url?.path.hasPrefix("/cloud") == true
    }

    private static let executionScript = #"""
    const sdk = window.__ysInputInject;
    const commands = JSON.parse(commandsJSON);
    if (commands.length === 1 && commands[0].method === 'releaseAll') {
      if (!sdk || Date.now() >= deadline || (window.__bgiMacInputEpoch ?? '') !== epoch)
        throw new Error('owned input release session expired');
      sdk.releaseAll();
      const s = sdk.status();
      if (s.pressedKeys.length || s.pressedButtons.length) throw new Error('owned input release failed');
      return JSON.stringify(s);
    }
    const check = () => {
      if (!sdk || window.__bgiMacInputEpoch !== epoch || Date.now() >= deadline || Date.now() >= (window.__bgiMacInputReadyUntil ?? 0))
        throw new Error('input session cancelled or expired');
      if (!document.hasFocus() || document.visibilityState !== 'visible')
        throw new Error('cloud game lost foreground focus');
      const s = sdk.status();
      if (s.rtcDataChannelState !== 'open' || s.gameDataStarted !== true)
        throw new Error('cloud game disconnected');
    };
    const wait = async ms => {
      const end = Date.now() + ms;
      while (Date.now() < end) { check(); await new Promise(r => setTimeout(r, Math.min(25, end-Date.now()))); }
      check();
    };
    check();
    for (const c of commands) {
      check();
      if (c.method === 'wait') { await wait(c.args[0]); continue; }
      if (!Object.hasOwn(sdk, c.method) || typeof sdk[c.method] !== 'function') throw new Error('unknown input method');
      await sdk[c.method](...c.args);
    }
    const s = sdk.status();
    if (commands.some(c => c.method === 'releaseAll') && (s.pressedKeys.length || s.pressedButtons.length))
      throw new Error('owned input release failed');
    return JSON.stringify(s);
    """#
}
