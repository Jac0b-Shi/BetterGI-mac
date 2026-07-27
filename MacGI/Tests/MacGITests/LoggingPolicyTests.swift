import Foundation
@testable import MacGI
import Testing

@Suite("Logging policies")
struct LoggingPolicyTests {
    @Test("Log levels have an explicit severity order")
    func severityOrder() {
        #expect(LogLevel.trace < .debug)
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .warn)
        #expect(LogLevel.warn < .error)
    }

    @MainActor
    @Test("Logging settings use defaults, persist, and reject invalid values")
    func settingsPersistence() {
        let suiteName = "bettergi-logging-settings-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = makeAppState(name: "logging-defaults", defaults: defaults)
        #expect(initial.hudMinimumLogLevel == .info)
        #expect(initial.fileMinimumLogLevel == .debug)

        initial.hudMinimumLogLevel = .warn
        initial.fileMinimumLogLevel = .error
        let persisted = makeAppState(name: "logging-persisted", defaults: defaults)
        #expect(persisted.hudMinimumLogLevel == .warn)
        #expect(persisted.fileMinimumLogLevel == .error)

        defaults.set("invalid", forKey: "logging.hudMinimumLevel")
        defaults.set("invalid", forKey: "logging.fileMinimumLevel")
        let fallback = makeAppState(name: "logging-fallback", defaults: defaults)
        #expect(fallback.hudMinimumLogLevel == .info)
        #expect(fallback.fileMinimumLogLevel == .debug)
    }

    @MainActor
    @Test("File and HUD thresholds filter independently")
    func independentDestinations() throws {
        let suiteName = "bettergi-logging-routing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(LogLevel.info.rawValue, forKey: "logging.hudMinimumLevel")
        defaults.set(LogLevel.debug.rawValue, forKey: "logging.fileMinimumLevel")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-logging-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appState = AppState(
            resourceStore: BGIRuntimeResourceStore(rootURL: root),
            launchArguments: ["betterGI-mac", "--dry-run"],
            userDefaults: defaults)

        appState.addLog(.trace, "trace-default-file-marker")
        appState.addLog(.debug, "debug-default-file-marker")
        appState.addLog(.info, "info-default-hud-marker")
        appState.flushRuntimeLogs()

        var content = try runtimeLogContent(root: root)
        #expect(!content.contains("trace-default-file-marker"))
        #expect(content.contains("debug-default-file-marker"))
        #expect(!appState.hudLogs.contains { $0.message == "debug-default-file-marker" })
        #expect(appState.hudLogs.contains { $0.message == "info-default-hud-marker" })

        appState.fileMinimumLogLevel = .error
        appState.addLog(.debug, "debug-memory-only-marker")
        appState.flushRuntimeLogs()
        content = try runtimeLogContent(root: root)
        #expect(appState.recentLogs.contains { $0.message == "debug-memory-only-marker" })
        #expect(!content.contains("debug-memory-only-marker"))

        appState.hudMinimumLogLevel = .error
        appState.fileMinimumLogLevel = .debug
        appState.addLog(.debug, "debug-file-only-marker")
        appState.flushRuntimeLogs()
        content = try runtimeLogContent(root: root)
        #expect(content.contains("debug-file-only-marker"))
        #expect(!appState.hudLogs.contains { $0.message == "debug-file-only-marker" })
    }

    @MainActor
    @Test("HUD applies its line limit after level filtering")
    func hudLimitAfterFiltering() {
        let suiteName = "bettergi-hud-logging-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = makeAppState(name: "hud-filtering", defaults: defaults)
        appState.recentLogs = []
        appState.hudMinimumLogLevel = .info
        appState.hudMaxLogLines = 2

        appState.addLog(.info, "old-info")
        appState.addLog(.debug, "newer-debug")
        appState.addLog(.warn, "newer-warning")
        appState.addLog(.error, "newest-error")

        #expect(appState.hudLogs.map(\.message) == [
            "newest-error",
            "newer-warning",
        ])
        #expect(appState.recentLogs.contains { $0.message == "newer-debug" })
    }
}

@MainActor
private func makeAppState(name: String, defaults: UserDefaults) -> AppState {
    AppState(
        resourceStore: BGIRuntimeResourceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "bettergi-\(name)-\(UUID().uuidString)",
                    isDirectory: true)),
        launchArguments: ["betterGI-mac", "--dry-run"],
        userDefaults: defaults)
}

private func runtimeLogContent(root: URL) throws -> String {
    let directory = root.appendingPathComponent("log", isDirectory: true)
    let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "log" }
    return try files
        .map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
}
