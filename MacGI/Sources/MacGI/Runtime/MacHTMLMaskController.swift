import AppKit
import Foundation
import WebKit

enum MacHTMLMaskError: LocalizedError {
    case invalidParameters(String)
    case missingWindow(String)
    case navigationRejected(String)
    case requestTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidParameters(let message): message
        case .missingWindow(let id): "HTML 遮罩窗口不存在或已关闭：\(id)"
        case .navigationRejected(let url): "HTML 遮罩拒绝访问：\(url)"
        case .requestTimedOut: "HTML 遮罩请求超时。"
        }
    }
}

@MainActor
final class MacHTMLMaskController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private static let maximumWindowCount = 5

    private final class WindowRecord {
        let id: String
        let handlerName: String
        let workDirectoryURL: URL
        let allowHTTP: Bool
        let allowedURLPatterns: [String]
        let panel: NSPanel
        let webView: WKWebView
        var clickThrough = true
        var navigationFinished = false
        var pendingMessages: [[String: Any]] = []

        init(
            id: String,
            handlerName: String,
            workDirectoryURL: URL,
            allowHTTP: Bool,
            allowedURLPatterns: [String],
            panel: NSPanel,
            webView: WKWebView
        ) {
            self.id = id
            self.handlerName = handlerName
            self.workDirectoryURL = workDirectoryURL
            self.allowHTTP = allowHTTP
            self.allowedURLPatterns = allowedURLPatterns
            self.panel = panel
            self.webView = webView
        }
    }

    private struct PendingResponse {
        let windowID: String
        let continuation: CheckedContinuation<String?, Error>
    }

    private weak var appState: AppState?
    private var windows: [String: WindowRecord] = [:]
    private var incomingMessages: [String: [[String: Any]]] = [:]
    private var pendingResponses: [String: PendingResponse] = [:]
    private var synchronizationTimer: Timer?

    init(appState: AppState) {
        self.appState = appState
    }

    func handle(method: String, parameters: [String: Any]?) async throws -> Any {
        switch method {
        case "htmlMask.show":
            return try await show(parameters)
        case "htmlMask.close":
            let id = try requiredString(parameters, "windowId")
            return ["closed": close(id)]
        case "htmlMask.closeAll":
            closeAll()
            return ["acknowledged": true]
        case "htmlMask.list":
            return ["windowIds": windows.keys.sorted()]
        case "htmlMask.exists":
            return ["exists": windows[try requiredString(parameters, "windowId")] != nil]
        case "htmlMask.setClickThrough":
            let id = try requiredString(parameters, "windowId")
            try setClickThrough(id, enabled: try requiredBool(parameters, "enabled"))
            return ["acknowledged": true]
        case "htmlMask.getClickThrough":
            let record = try requiredWindow(parameters)
            return ["enabled": record.clickThrough]
        case "htmlMask.toggleClickThrough":
            let record = try requiredWindow(parameters)
            try setClickThrough(record.id, enabled: !record.clickThrough)
            return ["acknowledged": true]
        case "htmlMask.send":
            let record = try requiredWindow(parameters)
            try await dispatchMessage(
                to: record,
                url: try requiredString(parameters, "url"),
                data: parameters?["data"] ?? NSNull(),
                requestID: nil)
            return ["acknowledged": true]
        case "htmlMask.respond":
            let record = try requiredWindow(parameters)
            try await dispatchMessage(
                to: record,
                url: try requiredString(parameters, "url"),
                data: parameters?["data"] ?? NSNull(),
                requestID: try requiredString(parameters, "requestId"))
            return ["acknowledged": true]
        case "htmlMask.request":
            let record = try requiredWindow(parameters)
            let response = try await request(
                record: record,
                url: try requiredString(parameters, "url"),
                data: parameters?["data"] ?? NSNull(),
                timeoutMilliseconds: try optionalInt(parameters, "timeoutMs") ?? 0)
            let value: Any = response ?? NSNull()
            return ["responseJSON": value]
        case "htmlMask.receive":
            let message = try await receive(
                windowID: try requiredString(parameters, "windowId"),
                timeoutMilliseconds: try optionalInt(parameters, "timeoutMs") ?? 0)
            return ["message": message ?? NSNull()]
        case "htmlMask.poll":
            let id = try requiredString(parameters, "windowId")
            _ = try window(id)
            let message: Any = dequeueMessage(windowID: id) ?? NSNull()
            return ["message": message]
        case "htmlMask.pollAll":
            let id = try requiredString(parameters, "windowId")
            _ = try window(id)
            let messages = incomingMessages.removeValue(forKey: id) ?? []
            incomingMessages[id] = []
            return ["messages": messages]
        default:
            throw MacHTMLMaskError.invalidParameters(
                "Unsupported HTML mask callback: \(method)")
        }
    }

    private func show(_ parameters: [String: Any]?) async throws -> Any {
        let rawURL = try requiredString(parameters, "url")
        let workDirectory = URL(
            fileURLWithPath: try requiredString(parameters, "workDir"),
            isDirectory: true).standardizedFileURL
        let requestedID = parameters?["id"] as? String
        let id = requestedID?.isEmpty == false ? requestedID! : UUID().uuidString
        let allowHTTP = parameters?["allowHTTP"] as? Bool ?? false
        let allowedPatterns = parameters?["allowedUrls"] as? [String] ?? []
        let pageURL = try validatedPageURL(
            rawURL,
            workDirectory: workDirectory,
            allowHTTP: allowHTTP,
            allowedPatterns: allowedPatterns)

        _ = close(id)
        guard windows.count < Self.maximumWindowCount else {
            throw MacHTMLMaskError.invalidParameters(
                "最多同时打开 \(Self.maximumWindowCount) 个 HTML 遮罩窗口。")
        }
        let handlerName =
            "betterGIHTMLMask_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: handlerName)
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.bridgeBootstrap(handlerName: handlerName),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false))
        if let ruleList = try await makeNetworkRuleList(
            allowHTTP: allowHTTP,
            allowedPatterns: allowedPatterns)
        {
            configuration.userContentController.add(ruleList)
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        let panel = makePanel(contentView: webView)
        let record = WindowRecord(
            id: id,
            handlerName: handlerName,
            workDirectoryURL: workDirectory,
            allowHTTP: allowHTTP,
            allowedURLPatterns: allowedPatterns,
            panel: panel,
            webView: webView)
        windows[id] = record
        incomingMessages[id] = []
        startSynchronizationTimerIfNeeded()
        synchronize(record)

        if pageURL.isFileURL {
            webView.loadFileURL(pageURL, allowingReadAccessTo: workDirectory)
        } else {
            webView.load(URLRequest(url: pageURL))
        }
        return ["windowId": id]
    }

    private func makePanel(contentView: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = contentView
        return panel
    }

    private func close(_ id: String) -> Bool {
        guard let record = windows.removeValue(forKey: id) else { return false }
        record.webView.configuration.userContentController.removeScriptMessageHandler(
            forName: record.handlerName)
        record.webView.stopLoading()
        record.panel.orderOut(nil)
        record.panel.close()
        incomingMessages.removeValue(forKey: id)
        let responseIDs = pendingResponses.compactMap { key, value in
            value.windowID == id ? key : nil
        }
        for requestID in responseIDs {
            pendingResponses.removeValue(forKey: requestID)?.continuation.resume(
                throwing: MacHTMLMaskError.missingWindow(id))
        }
        if windows.isEmpty {
            synchronizationTimer?.invalidate()
            synchronizationTimer = nil
        }
        return true
    }

    private func closeAll() {
        for id in Array(windows.keys) {
            _ = close(id)
        }
    }

    private func setClickThrough(_ id: String, enabled: Bool) throws {
        let record = try window(id)
        record.clickThrough = enabled
        record.panel.ignoresMouseEvents = enabled
        if !enabled, shouldPresentWindows {
            record.panel.orderFrontRegardless()
        }
    }

    private func request(
        record: WindowRecord,
        url: String,
        data: Any,
        timeoutMilliseconds: Int
    ) async throws -> String? {
        guard timeoutMilliseconds >= 0 else {
            throw MacHTMLMaskError.invalidParameters("timeoutMs 不能为负数。")
        }
        let requestID = UUID().uuidString
        return try await withCheckedThrowingContinuation { continuation in
            pendingResponses[requestID] = PendingResponse(
                windowID: record.id,
                continuation: continuation)
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.dispatchMessage(
                        to: record,
                        url: url,
                        data: data,
                        requestID: requestID)
                } catch {
                    self.pendingResponses.removeValue(forKey: requestID)?
                        .continuation.resume(throwing: error)
                }
            }
            if timeoutMilliseconds > 0 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(
                        for: .milliseconds(timeoutMilliseconds))
                    self?.pendingResponses.removeValue(forKey: requestID)?
                        .continuation.resume(throwing: MacHTMLMaskError.requestTimedOut)
                }
            }
        }
    }

    private func receive(
        windowID: String,
        timeoutMilliseconds: Int
    ) async throws -> Any? {
        guard timeoutMilliseconds >= 0 else {
            throw MacHTMLMaskError.invalidParameters("timeoutMs 不能为负数。")
        }
        _ = try window(windowID)
        let started = ContinuousClock.now
        while windows[windowID] != nil {
            if let message = dequeueMessage(windowID: windowID) {
                return message
            }
            if timeoutMilliseconds > 0,
               started.duration(to: .now) >= .milliseconds(timeoutMilliseconds)
            {
                return nil
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func dequeueMessage(windowID: String) -> [String: Any]? {
        guard var queue = incomingMessages[windowID], !queue.isEmpty else { return nil }
        let message = queue.removeFirst()
        incomingMessages[windowID] = queue
        return message
    }

    private func dispatchMessage(
        to record: WindowRecord,
        url: String,
        data: Any,
        requestID: String?
    ) async throws {
        guard windows[record.id] === record else {
            throw MacHTMLMaskError.missingWindow(record.id)
        }
        var message: [String: Any] = ["url": url, "data": data]
        if let requestID {
            message["requestId"] = requestID
        }
        guard record.navigationFinished else {
            record.pendingMessages.append(message)
            return
        }
        try await evaluate(message: message, in: record.webView)
    }

    private func evaluate(message: [String: Any], in webView: WKWebView) async throws {
        let data = try JSONSerialization.data(withJSONObject: message)
        let raw = String(decoding: data, as: UTF8.self)
        let quoted = String(decoding: try JSONEncoder().encode(raw), as: UTF8.self)
        _ = try await webView.evaluateJavaScript(
            "window.__betterGIHtmlMaskDispatch(\(quoted));")
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let record = windows.values.first(where: {
            $0.webView === message.webView && $0.handlerName == message.name
        }), let body = message.body as? [String: Any]
        else { return }

        let requestID = body["requestId"] as? String
        if let requestID,
           let pending = pendingResponses.removeValue(forKey: requestID)
        {
            do {
                pending.continuation.resume(
                    returning: try serializeJSON(body["data"] ?? NSNull()))
            } catch {
                pending.continuation.resume(throwing: error)
            }
            return
        }
        incomingMessages[record.id, default: []].append([
            "url": body["url"] as? String ?? "",
            "data": body["data"] ?? NSNull(),
            "requestId": requestID ?? NSNull(),
        ])
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let record = windows.values.first(where: { $0.webView === webView }) else {
            return
        }
        record.navigationFinished = true
        let messages = record.pendingMessages
        record.pendingMessages.removeAll()
        Task { @MainActor in
            for message in messages {
                do {
                    try await evaluate(message: message, in: webView)
                } catch {
                    appState?.addLog(
                        .error,
                        "HTML 遮罩消息发送失败：\(error.localizedDescription)")
                }
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let record = windows.values.first(where: { $0.webView === webView }),
              let url = navigationAction.request.url
        else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(isAllowed(
            url,
            workDirectory: record.workDirectoryURL,
            allowHTTP: record.allowHTTP,
            allowedPatterns: record.allowedURLPatterns) ? .allow : .cancel)
    }

    private func startSynchronizationTimerIfNeeded() {
        guard synchronizationTimer == nil else { return }
        synchronizationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                for record in self.windows.values {
                    self.synchronize(record)
                }
            }
        }
    }

    private var shouldPresentWindows: Bool {
        guard let appState,
              appState.runtimeLifecycle == .running,
              appState.isWindowValid,
              !appState.selectedWindow.isSynthetic
        else { return false }
        return !appState.hideHUDWhenGameUnfocused || appState.isGameWindowFrontmost
    }

    private func synchronize(_ record: WindowRecord) {
        guard shouldPresentWindows, let appState else {
            record.panel.orderOut(nil)
            return
        }
        let referenceMaxY = NSScreen.screens.first?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        let frame = HUDPanelController.appKitFrame(
            forQuartzFrame: appState.selectedWindow.captureRect,
            referenceMaxY: referenceMaxY)
        record.panel.setFrame(frame, display: true)
        if !record.panel.isVisible {
            record.panel.orderFrontRegardless()
        }
    }

    private func validatedPageURL(
        _ rawURL: String,
        workDirectory: URL,
        allowHTTP: Bool,
        allowedPatterns: [String]
    ) throws -> URL {
        guard let url = URL(string: rawURL), url.scheme != nil else {
            throw MacHTMLMaskError.invalidParameters("HTML 遮罩 URL 无效。")
        }
        guard isAllowed(
            url,
            workDirectory: workDirectory,
            allowHTTP: allowHTTP,
            allowedPatterns: allowedPatterns)
        else {
            throw MacHTMLMaskError.navigationRejected(rawURL)
        }
        return url
    }

    private func isAllowed(
        _ url: URL,
        workDirectory: URL,
        allowHTTP: Bool,
        allowedPatterns: [String]
    ) -> Bool {
        if url.isFileURL {
            let path = url.standardizedFileURL.path
            let root = workDirectory.standardizedFileURL.path
            return path == root || path.hasPrefix(root + "/")
        }
        if url.scheme == "data" || url.scheme == "about" {
            return true
        }
        guard allowHTTP, url.scheme == "http" || url.scheme == "https" else {
            return false
        }
        return allowedPatterns.contains {
            NSPredicate(format: "SELF LIKE[c] %@", $0).evaluate(with: url.absoluteString)
        }
    }

    private func makeNetworkRuleList(
        allowHTTP: Bool,
        allowedPatterns: [String]
    ) async throws -> WKContentRuleList? {
        var rules: [[String: Any]] = [[
            "trigger": ["url-filter": "^https?://.*"],
            "action": ["type": "block"],
        ]]
        if allowHTTP {
            for pattern in allowedPatterns {
                let escaped = NSRegularExpression.escapedPattern(for: pattern)
                    .replacingOccurrences(of: "\\*", with: ".*")
                rules.append([
                    "trigger": ["url-filter": "^\(escaped)$"],
                    "action": ["type": "ignore-previous-rules"],
                ])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: rules)
        let source = String(decoding: data, as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "bettergi-html-mask-\(UUID().uuidString)",
                encodedContentRuleList: source)
            { ruleList, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ruleList)
                }
            }
        }
    }

    private func requiredWindow(_ parameters: [String: Any]?) throws -> WindowRecord {
        try window(try requiredString(parameters, "windowId"))
    }

    private func window(_ id: String) throws -> WindowRecord {
        guard let record = windows[id] else {
            throw MacHTMLMaskError.missingWindow(id)
        }
        return record
    }

    private func requiredString(
        _ parameters: [String: Any]?,
        _ name: String
    ) throws -> String {
        guard let value = parameters?[name] as? String, !value.isEmpty else {
            throw MacHTMLMaskError.invalidParameters(
                "HTML 遮罩参数 \(name) 缺失。")
        }
        return value
    }

    private func requiredBool(
        _ parameters: [String: Any]?,
        _ name: String
    ) throws -> Bool {
        guard let value = parameters?[name] as? Bool else {
            throw MacHTMLMaskError.invalidParameters(
                "HTML 遮罩参数 \(name) 缺失。")
        }
        return value
    }

    private func optionalInt(
        _ parameters: [String: Any]?,
        _ name: String
    ) throws -> Int? {
        guard let raw = parameters?[name] else { return nil }
        guard let value = raw as? NSNumber else {
            throw MacHTMLMaskError.invalidParameters(
                "HTML 遮罩参数 \(name) 必须是整数。")
        }
        return value.intValue
    }

    private func serializeJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }

    private static func bridgeBootstrap(handlerName: String) -> String {
        """
        (() => {
          const post = message =>
            window.webkit.messageHandlers.\(handlerName).postMessage(message);
          window.htmlMask = {
            _callbacks: {},
            _seq: 0,
            request: function(url, data) {
              return new Promise(function(resolve, reject) {
                const id = '__req_' + (++window.htmlMask._seq);
                window.htmlMask._callbacks[id] = { resolve, reject };
                post({ url, data: data || {}, requestId: id });
              });
            },
            onMessage: null,
            _dispatch: function(raw) {
              try {
                const msg = JSON.parse(raw);
                if (msg.requestId && window.htmlMask._callbacks[msg.requestId]) {
                  window.htmlMask._callbacks[msg.requestId].resolve(msg);
                  delete window.htmlMask._callbacks[msg.requestId];
                } else if (window.htmlMask.onMessage) {
                  const result = window.htmlMask.onMessage(msg);
                  if (msg.requestId && result !== undefined) {
                    Promise.resolve(result).then(data => {
                      post({ requestId: msg.requestId, url: '/__response__', data });
                    });
                  }
                }
              } catch (error) {
                if (window.htmlMask.onMessage) window.htmlMask.onMessage(raw);
              }
            }
          };
          window.__betterGIHtmlMaskDispatch = raw => window.htmlMask._dispatch(raw);
        })();
        """
    }
}
