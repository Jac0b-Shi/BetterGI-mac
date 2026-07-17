import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI user script catalog")
struct BGIUserScriptCatalogTests {
    @Test("Catalog scans installed Windows-compatible User folders")
    func catalogScansInstalledWindowsCompatibleUserFolders() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-user-catalog-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        try createUserCatalogFixture(in: store.userURL)

        let snapshot = try BGIUserScriptCatalogLoader(store: store).loadSnapshot()

        #expect(snapshot.jsProjects.map(\.folderName) == ["AutoEntrust"])
        #expect(snapshot.jsProjects[0].manifest.name == "全自动每日委托")
        #expect(snapshot.jsIssues.map(\.path) == ["User/JsScript/Broken"])
        #expect(snapshot.combatStrategies.map(\.name) == ["群友分享/万能战斗策略", "冰水"])
        #expect(snapshot.geniusInvokationStrategies.map(\.name) == ["1.莫娜砂糖琴"])
        #expect(snapshot.oneDragonConfigs.map(\.name) == ["默认配置"])
        #expect(snapshot.scriptGroups.map(\.name) == ["每日调度"])
        #expect(snapshot.loadedScriptGroups.map(\.name) == ["每日调度"])
        #expect(snapshot.scriptGroupIssues.isEmpty)
        #expect(snapshot.keyMouseScripts.map(\.name) == ["录制样例"])

        let pathingChildren = snapshot.pathingRoot.children
        #expect(pathingChildren.map(\.fileName) == ["食材与炼金"])
        let pineNode = pathingChildren[0].children[0]
        #expect(pineNode.fileName == "松果")
        #expect(pineNode.iconURL?.lastPathComponent == "icon.ico")
        #expect(pineNode.children.map(\.fileName) == ["01-松果-望风角-5个"])
        #expect(pineNode.children[0].relativePath == "食材与炼金/松果/01-松果-望风角-5个.json")
    }

    @Test("Real migrated User folder is readable when present")
    func realMigratedUserFolderIsReadableWhenPresent() throws {
        let store = BGIRuntimeResourceStore.defaultStore()
        let userURL = store.userURL
        guard FileManager.default.fileExists(atPath: userURL.path) else {
            return
        }

        let snapshot = try BGIUserScriptCatalogLoader(store: store).loadSnapshot(createDirectories: false)
        let pathingFiles = flattenPathing(snapshot.pathingRoot).filter { !$0.isDirectory }

        #expect(snapshot.jsProjects.count >= 1)
        #expect(snapshot.combatStrategies.count >= 1)
        #expect(snapshot.geniusInvokationStrategies.count >= 1)
        #expect(pathingFiles.count >= 1)
        #expect(snapshot.jsIssues.isEmpty)
        #expect(snapshot.scriptGroupIssues.isEmpty)
    }

    @Test("Catalog output is deterministic regardless of filesystem enumeration order")
    func catalogOrderIsDeterministic() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-user-order-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))

        // Create files in reverse order to verify sorting is independent of creation order.
        try writeCatalogFixture("combat", relativePath: "AutoFight/群友分享/万能战斗策略.txt", under: store.userURL)
        try writeCatalogFixture("combat", relativePath: "AutoFight/冰水.txt", under: store.userURL)

        let snapshot = try BGIUserScriptCatalogLoader(store: store).loadSnapshot()
        #expect(snapshot.combatStrategies.map(\.name) == ["群友分享/万能战斗策略", "冰水"])
    }
}

private func createUserCatalogFixture(in userURL: URL) throws {
    try writeCatalogFixture(
        """
        {
          "manifest_version": 1,
          "name": "全自动每日委托",
          "version": "1.0.0",
          "settings_ui": "settings.json",
          "main": "main.js"
        }
        """,
        relativePath: "JsScript/AutoEntrust/manifest.json",
        under: userURL
    )
    try writeCatalogFixture("console.log('ok');\n", relativePath: "JsScript/AutoEntrust/main.js", under: userURL)
    try writeCatalogFixture("[]\n", relativePath: "JsScript/AutoEntrust/settings.json", under: userURL)
    try writeCatalogFixture(
        """
        {"name":"Broken","version":"1.0.0","main":"missing.js"}
        """,
        relativePath: "JsScript/Broken/manifest.json",
        under: userURL
    )
    try writeCatalogFixture("{}", relativePath: "AutoPathing/食材与炼金/松果/01-松果-望风角-5个.json", under: userURL)
    try writeCatalogFixture("ico", relativePath: "AutoPathing/食材与炼金/松果/icon.ico", under: userURL)
    try writeCatalogFixture("ini", relativePath: "AutoPathing/食材与炼金/松果/desktop.ini", under: userURL)
    try writeCatalogFixture("combat", relativePath: "AutoFight/冰水.txt", under: userURL)
    try writeCatalogFixture("combat", relativePath: "AutoFight/群友分享/万能战斗策略.txt", under: userURL)
    try writeCatalogFixture("tcg", relativePath: "AutoGeniusInvokation/1.莫娜砂糖琴.txt", under: userURL)
    try writeCatalogFixture(#"{"Name":"默认配置"}"#, relativePath: "OneDragon/默认配置.json", under: userURL)
    try writeCatalogFixture(#"{"index":1,"name":"每日调度","projects":[{"index":1,"name":"全自动每日委托","folderName":"AutoEntrust","type":"Javascript","status":"Enabled","schedule":"Daily","runNum":1,"jsScriptSettingsObject":{"country":"蒙德"}}]}"#, relativePath: "ScriptGroup/每日调度.json", under: userURL)
    try writeCatalogFixture("{}", relativePath: "KeyMouseScript/录制样例.json", under: userURL)
}

private func writeCatalogFixture(_ content: String, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func flattenPathing(_ node: BGIUserPathingTreeNode) -> [BGIUserPathingTreeNode] {
    [node] + node.children.flatMap(flattenPathing)
}
