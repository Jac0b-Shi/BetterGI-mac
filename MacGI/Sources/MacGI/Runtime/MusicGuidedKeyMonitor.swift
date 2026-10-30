import AppKit

/// Observes physical player input without posting, swallowing, or rewriting events.
@MainActor
final class MusicGuidedKeyMonitor {
    private var monitor: Any?
    var onKey: ((Int, Bool, Bool) -> Void)?
    var onExit: (() -> Void)?
    var onRedetect: (() -> Void)?
    var isGameFrontmost: (() -> Bool)?

    func start() throws {
        stop()
        guard MacGIPermissionRequester.accessibilityGranted else {
            throw BetterGICoreRPCError.protocolViolation("引导式跟弹需要辅助功能权限以监听真实按键。")
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.receive(event) }
        }
        guard monitor != nil else {
            throw BetterGICoreRPCError.protocolViolation("无法安装跟弹按键监听器。")
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        onKey = nil; onExit = nil; onRedetect = nil
    }

    private func receive(_ event: NSEvent) {
        guard event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) != Int64(ProcessInfo.processInfo.processIdentifier),
              !event.isARepeat else { return }
        let down = event.type == .keyDown
        // Key-up is delivered even after focus loss, so the Core can clear held chords.
        guard !down || isGameFrontmost?() == true else { return }
        if event.keyCode == 53, down { onExit?(); return }
        guard let text = event.charactersIgnoringModifiers?.uppercased(),
              text.utf8.count == 1, let code = text.utf8.first, (65...90).contains(code) else { return }
        if down, code == 82, event.modifierFlags.contains(.control) { onRedetect?(); return }
        onKey?(Int(code), down, !event.modifierFlags.intersection([.control, .option, .command]).isEmpty)
    }
}
