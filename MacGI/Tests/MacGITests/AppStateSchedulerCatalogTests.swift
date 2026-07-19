import Foundation
@testable import MacGI
import Testing

@Suite("AppState scheduler catalog")
struct AppStateSchedulerCatalogTests {
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

        #expect(appState.schedulerGroupsForCurrentSelection().map(\.name) == ["狗粮+锄地"])

        appState.selectedSchedulerGroupName = "不存在"
        #expect(appState.schedulerGroupsForCurrentSelection().map(\.name) == ["每日", "狗粮+锄地"])
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
