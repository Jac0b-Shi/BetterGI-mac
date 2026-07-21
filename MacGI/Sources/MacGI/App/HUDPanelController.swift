import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    private var appState: AppState?
    private var hudPanelController: HUDPanelController?
    private var windowTrackingTimer: Timer?

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
        windowTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak appState, weak controller] _ in
            Task { @MainActor in
                guard let appState, let controller else { return }
                let window = appState.refreshSelectedWindowGeometry()
                controller.synchronize(with: window)
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
        synchronize(with: appState.refreshSelectedWindowGeometry())
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

    func synchronize(with window: WindowInfo?) {
        guard let panel else { return }
        guard appState.isHUDVisible, let window, window.isOnScreen, !window.isSynthetic else {
            panel.orderOut(nil)
            return
        }
        let referenceMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        panel.setFrame(Self.appKitFrame(forQuartzFrame: window.captureRect, referenceMaxY: referenceMaxY), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    static func appKitFrame(forQuartzFrame frame: CGRect, referenceMaxY: CGFloat) -> NSRect {
        NSRect(x: frame.minX, y: referenceMaxY - frame.maxY, width: frame.width, height: frame.height)
    }
}
