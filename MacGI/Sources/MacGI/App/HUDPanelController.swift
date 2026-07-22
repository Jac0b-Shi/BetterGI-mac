import AppKit
import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    private var appState: AppState?
    private var hudPanelController: HUDPanelController?
    private var mapMaskPickerPanelController: MapMaskPickerPanelController?
    private let gameFocusObserver = GameFocusObserver()
    private var windowTrackingTimer: Timer?

    func configure(appState: AppState) {
        guard self.appState == nil else { return }
        self.appState = appState
        setApplicationIcon()
        let controller = HUDPanelController(appState: appState)
        let pickerController = MapMaskPickerPanelController(appState: appState)
        hudPanelController = controller
        mapMaskPickerPanelController = pickerController
        appState.onHUDPresentationChanged = { [weak self] visible in
            Task { @MainActor in
                if visible {
                    self?.hudPanelController?.show()
                } else {
                    self?.hudPanelController?.hide()
                    self?.mapMaskPickerPanelController?.hide()
                }
            }
        }
        gameFocusObserver.start(appState: appState)
        if appState.isHUDPresented {
            controller.show()
        }
        windowTrackingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) {
            [weak appState, weak controller, weak pickerController] _ in
            Task { @MainActor in
                guard let appState, let controller, let pickerController else { return }
                let window = appState.refreshSelectedWindowGeometry()
                controller.synchronize(with: window)
                pickerController.synchronize(with: window)
            }
        }
    }

    func showHUDIfNeeded() {
        guard appState?.isHUDPresented == true else { return }
        hudPanelController?.show()
    }

    func quit() {
        gameFocusObserver.stop()
        NSApp.terminate(nil)
    }

    private func setApplicationIcon() {
        guard let url = Bundle.macGIResources.url(forResource: "bettergi-logo", withExtension: "png", subdirectory: "Images")
            ?? Bundle.macGIResources.url(forResource: "bettergi-logo", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return
        }
        NSApp.applicationIconImage = image
    }
}

@MainActor
final class MapMaskPickerPanelController {
    private let appState: AppState
    private var panel: NSPanel?

    init(appState: AppState) {
        self.appState = appState
    }

    func hide() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        }
    }

    func synchronize(with window: WindowInfo?) {
        guard appState.isHUDPresented,
              appState.coreOverlayStore.state.isInBigMapUI,
              let window, window.isOnScreen, !window.isSynthetic else {
            hide()
            return
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        let referenceMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        let gameFrame = HUDPanelController.appKitFrame(
            forQuartzFrame: window.captureRect, referenceMaxY: referenceMaxY)
        panel.setFrame(Self.panelFrame(
            in: gameFrame, expanded: appState.isMapMaskPickerOpen), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .init(x: 0, y: 0, width: 70, height: 70),
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
        panel.ignoresMouseEvents = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        let hostingView = FixedFrameHostingView(
            rootView: MapMaskPickerView().environmentObject(appState))
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        return panel
    }

    static func panelFrame(in gameFrame: NSRect, expanded: Bool) -> NSRect {
        let scale = max(0.75, gameFrame.height / 1080)
        let buttonSize = max(58, 70 * scale)
        let width = expanded
            ? min(gameFrame.width - 128 * scale, 640 * scale)
            : buttonSize
        let height = expanded
            ? min(gameFrame.height - 20 * scale, gameFrame.height * 0.62 + buttonSize + 10 * scale)
            : buttonSize
        return NSRect(
            x: gameFrame.minX + 108 * gameFrame.width / 1920,
            y: gameFrame.minY + 22 * scale,
            width: max(buttonSize, width),
            height: max(buttonSize, height))
    }
}

private final class FixedFrameHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
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
        if panel?.isVisible == true {
            panel?.orderOut(nil)
        }
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
        guard appState.isHUDPresented, let window, window.isOnScreen, !window.isSynthetic else {
            hide()
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
