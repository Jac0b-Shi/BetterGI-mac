import AppKit
import SwiftUI
import WebKit

private struct ScriptRepositoryChannel: Identifiable, Equatable {
    let name: String
    let url: String

    var id: String { name }

    static let channels = [
        ScriptRepositoryChannel(
            name: "CNB",
            url: "https://cnb.cool/bettergi/bettergi-scripts-list"
        ),
        ScriptRepositoryChannel(
            name: "GitCode",
            url: "https://gitcode.com/huiyadanli/bettergi-scripts-list"
        ),
        ScriptRepositoryChannel(
            name: "GitHub",
            url: "https://github.com/babalae/bettergi-scripts-list"
        ),
        ScriptRepositoryChannel(name: "自定义", url: "")
    ]
}

struct ScriptRepositorySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scriptRepository.channel") private var selectedChannelName = "CNB"
    @AppStorage("scriptRepository.customURL") private var customURL = ""

    @State private var repositoryState: BetterGIScriptRepositoryState?
    @State private var statusText = "正在读取本地仓库状态..."
    @State private var error: String?
    @State private var isUpdating = false
    @State private var confirmingReset = false
    @State private var showingBrowser = false

    private var selectedChannel: ScriptRepositoryChannel {
        ScriptRepositoryChannel.channels.first { $0.name == selectedChannelName }
            ?? ScriptRepositoryChannel.channels[0]
    }

    private var repositoryURL: String {
        selectedChannel.name == "自定义" ? customURL : selectedChannel.url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("脚本仓库").font(.title2).bold()
                    Text("更新本地中央仓库后，可打开仓库浏览和订阅脚本。")
                        .foregroundStyle(BGIColors.mutedText)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            BGISectionCard("Git 一键更新", subtitle: statusText, symbolName: "arrow.triangle.branch") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("更新渠道", selection: $selectedChannelName) {
                        ForEach(ScriptRepositoryChannel.channels) { channel in
                            Text(channel.name).tag(channel.name)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(alignment: .firstTextBaseline) {
                        Text("仓库地址")
                            .frame(width: 76, alignment: .leading)
                        if selectedChannel.name == "自定义" {
                            TextField("https://...", text: $customURL)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text(repositoryURL)
                                .font(BGIFonts.console)
                                .foregroundStyle(BGIColors.mutedText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let error {
                        Text(error)
                            .foregroundStyle(BGIColors.danger)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        Button {
                            updateRepository()
                        } label: {
                            Label("更新仓库", systemImage: "icloud.and.arrow.down")
                        }
                        .disabled(isUpdating || repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button(role: .destructive) {
                            confirmingReset = true
                        } label: {
                            Label("重置仓库", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(isUpdating || repositoryState?.available != true)
                    }
                }
            }

            BGISectionCard("本地仓库", subtitle: repositorySummary, symbolName: "archivebox") {
                VStack(alignment: .leading, spacing: 12) {
                    if let path = repositoryState?.repositoryPath {
                        Text(path)
                            .font(BGIFonts.console)
                            .foregroundStyle(BGIColors.mutedText)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    HStack {
                        Button {
                            showingBrowser = true
                        } label: {
                            Label("打开仓库", systemImage: "safari")
                        }
                        .disabled(!canOpenRepository)

                        Button {
                            updateSubscriptions()
                        } label: {
                            Label("一键更新订阅", systemImage: "arrow.down.circle")
                        }
                        .disabled(
                            isUpdating ||
                            repositoryState?.subscribedPaths.isEmpty != false ||
                            repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        Button {
                            Task { await refreshState() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("刷新仓库状态")
                        .disabled(isUpdating)
                        Spacer()
                        if let count = repositoryState?.subscribedPaths.count {
                            Text("\(count) 项订阅")
                                .font(BGIFonts.caption)
                                .foregroundStyle(BGIColors.mutedText)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 470)
        .task { await refreshState() }
        .confirmationDialog("确定要重置脚本仓库吗？", isPresented: $confirmingReset) {
            Button("重置仓库", role: .destructive) {
                resetRepository()
            }
            Button("取消", role: .cancel) {
                confirmingReset = false
            }
        } message: {
            Text("重置后需要重新更新仓库，已安装到用户目录的脚本不会被删除。")
        }
        .sheet(isPresented: $showingBrowser) {
            if let path = repositoryState?.webIndexPath {
                ScriptRepositoryBrowser(indexPath: path)
                    .environmentObject(appState)
            }
        }
    }

    private var canOpenRepository: Bool {
        repositoryState?.available == true && repositoryState?.webIndexPath != nil
    }

    private var repositorySummary: String {
        guard let state = repositoryState else { return "正在读取仓库状态..." }
        if !state.available { return "尚未更新本地脚本仓库。" }
        if state.webIndexPath == nil { return "仓库数据已就绪，但仓库浏览器资源尚未准备完成。" }
        return "仓库数据和浏览器资源已就绪。"
    }

    private func updateRepository() {
        isUpdating = true
        error = nil
        statusText = "正在从 \(selectedChannel.name) 更新脚本仓库..."
        Task {
            do {
                let result = try await appState.updateScriptRepository(
                    channel: selectedChannel.name,
                    url: repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                statusText = result.status == "alreadyUpToDate"
                    ? "脚本仓库已是最新。"
                    : "脚本仓库更新完成。"
                await refreshState()
            } catch {
                self.error = error.localizedDescription
                statusText = "脚本仓库更新失败。"
            }
            isUpdating = false
        }
    }

    private func resetRepository() {
        isUpdating = true
        error = nil
        statusText = "正在重置脚本仓库..."
        Task {
            do {
                try await appState.resetScriptRepository()
                statusText = "脚本仓库已重置，请重新更新。"
                await refreshState()
            } catch {
                self.error = error.localizedDescription
                statusText = "脚本仓库重置失败。"
            }
            isUpdating = false
        }
    }

    private func updateSubscriptions() {
        isUpdating = true
        error = nil
        statusText = "正在更新仓库和全部订阅..."
        Task {
            do {
                let result = try await appState.updateSubscribedScripts(
                    channel: selectedChannel.name,
                    url: repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                if result.failureCount == 0 {
                    statusText = result.attemptedCount == 0
                        ? "没有可更新的订阅。"
                        : "已更新 \(result.successCount) 项订阅。"
                } else {
                    statusText =
                        "已更新 \(result.successCount) 项，\(result.failureCount) 项失败。"
                    error = result.failedPaths.joined(separator: "\n")
                }
                await refreshState()
            } catch {
                self.error = error.localizedDescription
                statusText = "一键更新订阅失败。"
            }
            isUpdating = false
        }
    }

    private func refreshState() async {
        do {
            repositoryState = try await appState.loadScriptRepositoryState()
            if repositoryState?.available == true, !isUpdating {
                statusText = "本地脚本仓库可用。"
            } else if !isUpdating {
                statusText = "尚未更新本地脚本仓库。"
            }
        } catch {
            self.error = error.localizedDescription
            statusText = "无法读取脚本仓库状态。"
        }
    }
}

private struct ScriptRepositoryBrowser: View {
    @Environment(\.dismiss) private var dismiss
    let indexPath: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Genshin Copilot Scripts").font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            Divider()
            ScriptRepositoryWebView(indexPath: indexPath)
        }
        .frame(minWidth: 1120, idealWidth: 1400, minHeight: 680, idealHeight: 820)
        .background(
            ResizableSheetWindow(
                minimumContentSize: NSSize(width: 1120, height: 680)
            )
        )
    }
}

private struct ResizableSheetWindow: NSViewRepresentable {
    let minimumContentSize: NSSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWindow(for: view)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.contentMinSize = minimumContentSize
        }
    }
}

private struct ScriptRepositoryWebView: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState
    let indexPath: String

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        userContentController.addScriptMessageHandler(
            context.coordinator,
            contentWorld: .page,
            name: "repoWebBridge"
        )
        userContentController.addUserScript(WKUserScript(
            source: Self.bridgeBootstrap,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedPath != indexPath else { return }
        context.coordinator.loadedPath = indexPath
        let indexURL = URL(fileURLWithPath: indexPath)
        webView.loadFileURL(
            indexURL,
            allowingReadAccessTo: indexURL.deletingLastPathComponent()
        )
    }

    private static let bridgeBootstrap = """
        (() => {
          const invoke = (method, args) =>
            window.webkit.messageHandlers.repoWebBridge.postMessage({ method, args });
          const bridge = new Proxy({}, {
            get: (_, method) => (...args) => invoke(String(method), args)
          });
          window.chrome = window.chrome || {};
          window.chrome.webview = window.chrome.webview || {};
          window.chrome.webview.hostObjects = { repoWebBridge: bridge };
        })();
        """

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate, WKUIDelegate {
        weak var appState: AppState?
        var loadedPath: String?

        init(appState: AppState) {
            self.appState = appState
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) async -> (Any?, String?) {
            guard let body = message.body as? [String: Any],
                  let method = body["method"] as? String,
                  let appState
            else {
                return (nil, "Invalid repository bridge request.")
            }
            let arguments = body["args"] as? [Any] ?? []
            do {
                return (
                    try await invoke(method: method, arguments: arguments, appState: appState),
                    nil
                )
            } catch {
                return (nil, error.localizedDescription)
            }
        }

        private func invoke(method: String, arguments: [Any], appState: AppState) async throws -> Any {
            switch method {
            case "GetRepoJson":
                return try await appState.scriptRepositoryRepoJSON()
            case "GetSubscribedScriptPaths":
                return try await appState.scriptRepositorySubscribedPathsJSON()
            case "GetFile":
                return try await appState.scriptRepositoryFile(
                    path: try stringArgument(arguments, at: 0)
                )
            case "ImportUri":
                guard confirmImport() else { return false }
                _ = try await appState.importScriptRepositoryURI(
                    try stringArgument(arguments, at: 0)
                )
                return true
            case "UpdateSubscribed":
                return try await appState.resetScriptRepositoryUpdateFlag(
                    path: try stringArgument(arguments, at: 0)
                )
            case "ClearUpdate":
                return try await appState.clearScriptRepositoryUpdateFlags()
            case "GetGuideStatus":
                return try await appState.scriptRepositoryGuideStatus()
            case "SetGuideStatus":
                return try await appState.setScriptRepositoryGuideStatus(
                    try boolArgument(arguments, at: 0)
                )
            default:
                throw BetterGICoreRPCError.protocolViolation(
                    "Unsupported repository bridge method: \(method)"
                )
            }
        }

        private func confirmImport() -> Bool {
            let alert = NSAlert()
            alert.messageText = "脚本订阅"
            alert.informativeText = "是否导入并覆盖所选脚本或文件夹？脚本声明的保存文件会保留。"
            alert.addButton(withTitle: "确认导入")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .informational
            return alert.runModal() == .alertFirstButtonReturn
        }

        private func stringArgument(_ arguments: [Any], at index: Int) throws -> String {
            guard arguments.indices.contains(index), let value = arguments[index] as? String else {
                throw BetterGICoreRPCError.protocolViolation("Repository bridge string argument is missing.")
            }
            return value
        }

        private func boolArgument(_ arguments: [Any], at index: Int) throws -> Bool {
            guard arguments.indices.contains(index), let value = arguments[index] as? Bool else {
                throw BetterGICoreRPCError.protocolViolation("Repository bridge boolean argument is missing.")
            }
            return value
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == true,
               url.scheme != "file",
               url.scheme != "about" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }
    }
}
