import Foundation
@testable import MacGI
import Testing

@Suite("AppState scheduler catalog")
struct AppStateSchedulerCatalogTests {
    @Test("Script settings preserve every JSON value kind")
    func scriptSettingsPreserveEveryJSONValueKind() throws {
        let source = Data(
            """
            {
              "null": null,
              "string": "value",
              "bool": true,
              "integer": 42,
              "number": 2.5,
              "strings": ["a", "b"],
              "array": [1, false, null, {"nested": "value"}],
              "object": {"enabled": true, "count": 3}
            }
            """.utf8
        )
        let raw = try #require(
            JSONSerialization.jsonObject(with: source) as? [String: Any]
        )
        let values = try raw.mapValues(BetterGIJSONValue.init(any:))
        let roundTrippedData = try JSONSerialization.data(
            withJSONObject: values.mapValues(\.any),
            options: [.sortedKeys]
        )
        let roundTrippedRaw = try #require(
            JSONSerialization.jsonObject(with: roundTrippedData) as? [String: Any]
        )

        #expect(try roundTrippedRaw.mapValues(BetterGIJSONValue.init(any:)) == values)
    }

    @Test("Debug Core resolver locates the staged SwiftPM helper")
    func debugCoreResolverLocatesStagedHelper() throws {
        let buildRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-core-resolver-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: buildRoot.deletingLastPathComponent()) }
        let helper = buildRoot
            .appendingPathComponent("BetterGICore", isDirectory: true)
            .appendingPathComponent("BetterGenshinImpact.Core.Host")
        try FileManager.default.createDirectory(
            at: helper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: helper)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )
        let appExecutable = buildRoot
            .appendingPathComponent("arm64-apple-macosx/debug", isDirectory: true)
            .appendingPathComponent("betterGI-mac")

        #expect(BetterGICoreProcessSupervisor.resolveDevelopmentExecutableURL(
            from: appExecutable
        ) == helper)
    }

    @MainActor
    @Test("AppState does not report capture throughput before a real frame")
    func appStateStartsWithoutSyntheticCaptureMetrics() {
        let appState = AppState(resourceStore: BGIRuntimeResourceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("bettergi-mac-capture-state-test-\(UUID().uuidString)", isDirectory: true)
        ))

        #expect(appState.captureStatus == .missing)
        #expect(appState.captureFPS == 0)
    }

    @MainActor
    @Test("AppState does not bypass Core by parsing User ScriptGroup locally")
    func appStateDoesNotFallbackToLocalScriptGroupParsing() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-appstate-scheduler-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        try writeAppStateSchedulerFixture(
            """
            {
              "index": 1,
              "name": "狗粮+锄地",
              "projects": [
                {
                  "index": 1,
                  "name": "锄地一条龙",
                  "folderName": "AutoHoeingOneDragon",
                  "type": "Javascript",
                  "status": "Enabled",
                  "schedule": "Daily",
                  "runNum": 1,
                  "jsScriptSettingsObject": {
                    "accountName": "默认账户",
                    "targetMonsters": "愚人众特辖队，巡陆艇"
                  }
                }
              ]
            }
            """,
            relativePath: "ScriptGroup/狗粮+锄地.json",
            under: store.userURL
        )

        let appState = AppState(resourceStore: store)
        appState.beginCoreStartup()
        for _ in 0..<100 where appState.schedulerCatalogIssues.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(appState.schedulerGroups.isEmpty)
        #expect(appState.selectedSchedulerGroupName.isEmpty)
        #expect(appState.schedulerCatalogStatus == "Core unavailable")
        #expect(appState.schedulerCatalogIssues.count == 1)
    }

    @MainActor
    @Test("AppState runs only the selected scheduler group")
    func appStateRunsOnlyTheSelectedSchedulerGroup() throws {
        let appState = AppState(resourceStore: BGIRuntimeResourceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("bettergi-mac-empty-scheduler-test-\(UUID().uuidString)", isDirectory: true)
        ))
        appState.schedulerGroups = [
            BetterGIScriptGroupSummary(name: "每日", path: "User/ScriptGroup/每日.json", index: 1, projects: []),
            BetterGIScriptGroupSummary(name: "狗粮+锄地", path: "User/ScriptGroup/狗粮+锄地.json", index: 2, projects: [])
        ]
        appState.selectedSchedulerGroupName = "狗粮+锄地"

        #expect(appState.selectedSchedulerGroup?.name == "狗粮+锄地")

        appState.selectedSchedulerGroupName = "不存在"
        #expect(appState.selectedSchedulerGroup == nil)
    }

    @MainActor
    @Test("Scheduler readiness never invents a visual selection")
    func schedulerReadinessRequiresCoreWindowAndSelection() {
        let appState = AppState(resourceStore: BGIRuntimeResourceStore(
            rootURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("bettergi-mac-scheduler-readiness-test-\(UUID().uuidString)", isDirectory: true)
        ))
        appState.schedulerGroups = [
            BetterGIScriptGroupSummary(name: "狗粮+锄地", path: "User/ScriptGroup/狗粮+锄地.json", index: 1, projects: [])
        ]

        #expect(appState.selectedSchedulerGroup == nil)
        #expect(!appState.canRunScheduler)
        #expect(appState.schedulerRunReadiness == "Core 尚未就绪")

        appState.coreStatus = .ok
        #expect(appState.schedulerRunReadiness == "请先启动 BetterGI 运行时")

        appState.runtimeLifecycle = .running
        #expect(appState.schedulerRunReadiness == "尚未选择配置组")

        appState.selectedSchedulerGroupName = "狗粮+锄地"
        appState.selectedWindow = .unavailable()
        #expect(appState.schedulerRunReadiness == "尚未选择真实游戏窗口")
    }
}

private func writeAppStateSchedulerFixture(_ content: String, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
}
