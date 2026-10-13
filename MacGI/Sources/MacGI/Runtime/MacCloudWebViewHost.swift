import AppKit
@preconcurrency import WebKit

private final class CloudGameWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// One persistent national-server profile; login and queueing stay inside the official page.
@MainActor
final class MacCloudWebViewHost: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private(set) var window: NSWindow!
    private(set) var webView: WKWebView!
    private(set) var bridge: WKWebInputBridge!
    private(set) var ready = false
    private var viewport: [String: Any]?
    private var loginWindows: [NSWindow] = []
    private var pollingTask: Task<Void, Never>?
    private var lastFrameCounter: Double?
    private var lastFrameAt = Date.distantPast
    private var lastPollAt = Date.distantPast
    private var navigationEpoch: UInt64 = 0
    var onStatus: ((String, Bool) -> Void)?
    var onUnavailable: (() -> Void)?
    var onCloseRequested: (() -> Void)?

    init(defaults: UserDefaults) throws {
        super.init()
        let key = "cloud.cn.webProfileID"
        let identifier = defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        defaults.set(identifier.uuidString, forKey: key)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: identifier)
        config.mediaTypesRequiringUserActionForPlayback = []
        guard let url = Bundle.macGIResources.url(forResource: "ys-input-inject", withExtension: "js", subdirectory: "Resources/CloudGame") else {
            throw CloudWebInputError.pageFailure("缺少上游 Web SDK 资源")
        }
        let sdk = try String(contentsOf: url, encoding: .utf8)
        config.userContentController.addUserScript(WKUserScript(source:
            "if (location.origin === 'https://ys.mihoyo.com' && location.pathname.startsWith('/cloud')) {\n" + sdk + "\n}",
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .page))
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
#if DEBUG
        webView.isInspectable = true
#endif
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let size = CloudGameGeometry.fittedWindowSize(CGSize(width: 1280, height: 720), visibleSize: screen)
        window = CloudGameWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.title = "云原神（国服）"
        window.backgroundColor = .black
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = webView
        window.center()
        bridge = WKWebInputBridge(webView: webView)
        bridge.canDispatch = { [weak self] in self?.verifyReady() == true }
        bridge.onFailure = { [weak self] message in self?.invalidate("输入已暂停：\(message)") }
    }

    func open() {
        focus()
        if webView.url == nil { webView.load(URLRequest(url: URL(string: "https://ys.mihoyo.com/cloud/?autobegin=1")!)) }
        if pollingTask == nil {
            pollingTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    do { try await Task.sleep(for: .milliseconds(250)) } catch { break }
                }
            }
        }
    }

    func focus() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }

    func resize(width: CGFloat) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let size = CloudGameGeometry.fittedWindowSize(CGSize(width: width, height: width * 9 / 16), visibleSize: screen.visibleFrame.size)
        invalidate("窗口尺寸变化，正在重新确认视频区域。")
        window.setContentSize(size)
        window.center()
    }

    func verifyReady() -> Bool {
        guard ready else { return false }
        guard Date().timeIntervalSince(lastFrameAt) < 2.5, Date().timeIntervalSince(lastPollAt) < 2.5 else {
            invalidate("视频或页面状态超时，自动化已停止。")
            return false
        }
        return true
    }

    func windowInfo() -> WindowInfo? {
        guard window.isVisible, window.windowNumber > 0,
              let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]],
              let row = rows.first,
              let bounds = row[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        let crop = viewport.flatMap { CloudGameGeometry.videoRect($0, in: frame) }
        // Match SCK's 1920px cap, rather than advertising the monitor's uncapped Retina scale.
        let scale = min(window.backingScaleFactor, 1920 / max(1, frame.width))
        return WindowInfo(id: CGWindowID(window.windowNumber), ownerPID: ProcessInfo.processInfo.processIdentifier,
                          ownerName: "betterGI-mac", title: window.title, frame: frame, layer: 0,
                          isOnScreen: true, scaleFactor: scale, contentRectOverride: crop, isHostedCloud: true)
    }

    func close() async {
        pollingTask?.cancel(); pollingTask = nil
        await bridge.releaseAndSuspend()
        ready = false; viewport = nil
        for popup in loginWindows {
            (popup.contentView as? WKWebView)?.stopLoading()
            popup.delegate = nil; popup.close()
        }
        loginWindows.removeAll()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil) // Tear down the page's RTC connection after owned release.
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        window.delegate = nil; window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender !== window { return true }
        onCloseRequested?(); return false
    }
    func windowWillClose(_ notification: Notification) {
        if let popup = notification.object as? NSWindow { loginWindows.removeAll { $0 === popup } }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        navigationEpoch &+= 1
        viewport = nil; lastFrameCounter = nil
        invalidate("正在加载国服云原神，请在游戏窗口内登录并进入游戏。")
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if webView === self.webView { invalidate(error.localizedDescription) } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if webView === self.webView { invalidate(error.localizedDescription) } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if webView === self.webView { invalidate("网页进程退出，请关闭后重新打开云原神。") } }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        decisionHandler(scheme == "https" || scheme == "http" || scheme == "about" ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.request.url?.scheme == "https" else { return nil }
        let popupView = WKWebView(frame: .zero, configuration: configuration)
        popupView.navigationDelegate = self; popupView.uiDelegate = self
        let popup = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 720),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        popup.title = "云原神网页"; popup.contentView = popupView
        popup.isReleasedWhenClosed = false; popup.delegate = self
        loginWindows.append(popup)
        popup.center(); popup.makeKeyAndOrderFront(nil)
        return popupView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let popup = loginWindows.first(where: { $0.contentView === webView }) { popup.close() }
    }

    private func invalidate(_ message: String) {
        let wasReady = ready
        ready = false
        bridge.suspend()
        onStatus?(message, false)
        if wasReady { onUnavailable?() }
    }

    private func poll() async {
        guard WKWebInputBridge.isGameOrigin(webView.url) else { return }
        let epoch = navigationEpoch
        do {
            let response = try await webView.callAsyncJavaScript(Self.statusScript, arguments: [:], in: nil, contentWorld: .page)
            guard epoch == navigationEpoch, WKWebInputBridge.isGameOrigin(webView.url) else { return }
            guard let json = response as? String,
                  let result = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let sdk = result["sdk"] as? [String: Any],
                  let video = result["video"] as? [String: Any],
                  let counter = video["counter"] as? Double,
                  sdk["rtcDataChannelState"] as? String == "open", sdk["gameDataStarted"] as? Bool == true,
                  video["playing"] as? Bool == true else {
                invalidate("等待登录、排队或视频连接；输入 SDK 尚未就绪。")
                return
            }
            if lastFrameCounter != counter { lastFrameCounter = counter; lastFrameAt = Date() }
            guard Date().timeIntervalSince(lastFrameAt) < 2.5 else { invalidate("视频帧停止更新，自动化已暂停。" ); return }
            viewport = video
            guard let info = windowInfo(), info.contentRectOverride != nil else { invalidate("未能确认游戏视频区域。" ); return }
            _ = try await webView.evaluateJavaScript("window.__bgiMacInputReadyUntil = Date.now() + 2500")
            guard epoch == navigationEpoch else { return }
            lastPollAt = Date()
            ready = true
            onStatus?("视频与 Web SDK 已就绪；首版自动化需要游戏窗口保持前台。", true)
        } catch {
            if epoch == navigationEpoch { invalidate("无法读取页面状态：\(error.localizedDescription)") }
        }
    }

    private static let statusScript = #"""
    const sdk = window.__ysInputInject?.status();
    const v = [...document.querySelectorAll('video')].filter(v => {
      const r = v.getBoundingClientRect(); return r.width >= 320 && r.height >= 180 && v.videoWidth > 0;
    }).sort((a,b) => b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight)[0];
    if (!sdk || !v) return JSON.stringify({});
    if (!window.__bgiVideoFrames) window.__bgiVideoFrames = new WeakMap();
    let record = window.__bgiVideoFrames.get(v);
    if (!record) {
      record = { count: 0 }; window.__bgiVideoFrames.set(v,record);
      if (v.requestVideoFrameCallback) {
        const frame = () => { record.count++; v.requestVideoFrameCallback(frame); };
        v.requestVideoFrameCallback(frame);
      }
    }
    const r = v.getBoundingClientRect();
    let x=r.x,y=r.y,width=r.width,height=r.height;
    // Exclude CSS object-fit letterboxing from OCR and normalized input coordinates.
    if (getComputedStyle(v).objectFit === 'contain') {
      const ratio = v.videoWidth/v.videoHeight;
      if (width/height > ratio) { const w=height*ratio; x+=(width-w)/2; width=w; }
      else { const h=width/ratio; y+=(height-h)/2; height=h; }
    }
    const counter = v.requestVideoFrameCallback ? record.count : (v.webkitDecodedFrameCount ?? v.currentTime);
    return JSON.stringify({sdk,video:{x,y,width,height,counter,playing:!v.paused && !v.ended && v.readyState>=2}});
    """#
}
