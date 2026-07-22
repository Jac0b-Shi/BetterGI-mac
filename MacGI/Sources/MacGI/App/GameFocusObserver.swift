import AppKit

enum HUDPresentationPolicy {
    static func shouldPresent(
        hudRequested: Bool,
        runtimeLifecycle: RuntimeLifecycle,
        windowValid: Bool,
        hideWhenUnfocused: Bool,
        gameFrontmost: Bool,
        layoutEditing: Bool,
        macGIFrontmost: Bool
    ) -> Bool {
        hudRequested
            && runtimeLifecycle == .running
            && windowValid
            && (!hideWhenUnfocused || gameFrontmost || (layoutEditing && macGIFrontmost))
    }
}

@MainActor
final class GameFocusObserver: NSObject {
    private weak var appState: AppState?
    private var delayedRecheckTask: Task<Void, Never>?

    func start(appState: AppState) {
        stop()
        self.appState = appState

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(applicationDeactivated(_:)),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(environmentChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(sessionResigned(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil)
        center.addObserver(
            self,
            selector: #selector(environmentChanged(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil)

        appState.refreshGameWindowFocus()
    }

    func stop() {
        delayedRecheckTask?.cancel()
        delayedRecheckTask = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        appState = nil
    }

    @objc
    private func applicationActivated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication else {
            scheduleDelayedRecheck()
            return
        }

        if application.processIdentifier == appState?.selectedWindow.ownerPID {
            scheduleDelayedRecheck()
        } else {
            delayedRecheckTask?.cancel()
            appState?.updateGameWindowFocus(frontmostPID: application.processIdentifier)
        }
    }

    @objc
    private func applicationDeactivated(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication,
              application.processIdentifier == appState?.selectedWindow.ownerPID else {
            return
        }
        delayedRecheckTask?.cancel()
        appState?.updateGameWindowFocus(frontmostPID: nil)
    }

    @objc
    private func environmentChanged(_ notification: Notification) {
        scheduleDelayedRecheck()
    }

    @objc
    private func sessionResigned(_ notification: Notification) {
        delayedRecheckTask?.cancel()
        appState?.updateGameWindowFocus(frontmostPID: nil)
    }

    private func scheduleDelayedRecheck() {
        delayedRecheckTask?.cancel()
        delayedRecheckTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.appState?.refreshGameWindowFocus()
        }
    }
}
