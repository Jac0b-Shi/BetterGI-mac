import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    private var appState: AppState?
    private var hudPanelController: HUDPanelController?
    private var heartbeatTimer: Timer?

    func configure(appState: AppState) {
        guard self.appState == nil else { return }
        self.appState = appState
        setApplicationIcon()
        let controller = HUDPanelController(appState: appState)
        hudPanelController = controller
        appState.onHUDVisibilityChanged = { [weak self] visible in
            Task { @MainActor in
                visible ? self?.hudPanelController?.show() : self?.hudPanelController?.hide()
            }
        }
        if appState.showHUDOnStart && appState.isHUDVisible {
            controller.show()
        }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak appState] _ in
            Task { @MainActor in
                guard let appState else { return }
                if appState.appStatus == .running {
                    appState.addTestLog()
                }
            }
        }
    }

    func showHUDIfNeeded() {
        guard appState?.isHUDVisible == true else { return }
        hudPanelController?.show()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func setApplicationIcon() {
        guard let url = Bundle.module.url(forResource: "bettergi-logo", withExtension: "png", subdirectory: "Images")
            ?? Bundle.module.url(forResource: "bettergi-logo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return
        }
        NSApp.applicationIconImage = image
    }
}

@MainActor
final class HUDPanelController {
    private let appState: AppState
    private var panel: NSPanel?
    private let preferredPanelSize = NSSize(width: 960, height: 540)

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        updateFrame()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .init(origin: .zero, size: preferredPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.contentView = NSHostingView(rootView: HUDView().environmentObject(appState))
        return panel
    }

    private func updateFrame() {
        guard let panel else { return }
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let padding: CGFloat = 24
        let width = min(preferredPanelSize.width, max(640, screenFrame.width - padding * 2))
        let height = min(preferredPanelSize.height, max(360, screenFrame.height - padding * 2), width * 9 / 16)
        let origin = NSPoint(
            x: screenFrame.maxX - width - padding,
            y: screenFrame.minY + padding
        )
        panel.setFrame(.init(origin: origin, size: .init(width: width, height: height)), display: true)
    }
}
