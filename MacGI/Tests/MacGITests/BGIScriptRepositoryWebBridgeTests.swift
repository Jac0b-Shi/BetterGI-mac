import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI script repository web bridge")
struct BGIScriptRepositoryWebBridgeTests {
    @Test("Web bridge prefers repo_updated.json and can clear update markers")
    func webBridgePrefersUpdatedIndexAndCanClearMarkers() throws {
        let fixture = try WebBridgeFixture()
        defer { fixture.cleanup() }

        try fixture.writeRepositoryIndex(hasUpdate: nil)
        try fixture.writeUpdatedRepositoryIndex(hasUpdate: true)

        #expect(try fixture.bridge.repoJSON().contains("\"hasUpdate\" : true"))
        #expect(try fixture.bridge.clearUpdateMarkers())
        #expect(try fixture.bridge.repoJSON().contains("hasUpdate") == false)
    }

    @Test("Web bridge resets hasUpdate on a selected path subtree")
    func webBridgeResetsHasUpdateOnSelectedPathSubtree() throws {
        let fixture = try WebBridgeFixture()
        defer { fixture.cleanup() }

        try fixture.writeRepositoryIndex(hasUpdate: nil)
        try fixture.writeUpdatedRepositoryIndex(hasUpdate: true)

        #expect(try fixture.bridge.resetUpdateFlag(forRepositoryPath: "js/demo"))
        let json = try fixture.bridge.repoJSON()
        let jsNode = try repoWebBridgeNode(path: ["js"], json: json)
        let demoNode = try repoWebBridgeNode(path: ["js", "demo"], json: json)
        let nestedNode = try repoWebBridgeNode(path: ["js", "demo", "nested"], json: json)

        #expect(jsNode["hasUpdate"] as? Bool == true)
        #expect(demoNode["hasUpdate"] as? Bool == false)
        #expect(nestedNode["hasUpdate"] as? Bool == false)
    }

    @Test("Web bridge reads text and image files but rejects traversal and unsupported extensions")
    func webBridgeReadsAllowedFilesAndRejectsUnsafePaths() throws {
        let fixture = try WebBridgeFixture()
        defer { fixture.cleanup() }

        try fixture.writeRepositoryIndex(hasUpdate: nil)
        try fixture.writeRepositoryFile("console.log('demo');\n", relativePath: "repo/js/demo/index.js")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        try fixture.writeRepositoryFile(imageData, relativePath: "repo/js/demo/icon.png")
        try fixture.writeRepositoryFile("secret\n", relativePath: "repo/js/demo/secret.exe")

        #expect(fixture.bridge.filePayload(forRepositoryPath: "js/demo/index.js") == "console.log('demo');\n")
        #expect(fixture.bridge.filePayload(forRepositoryPath: "js/demo/icon.png") == imageData.base64EncodedString())
        #expect(fixture.bridge.filePayload(forRepositoryPath: "../repo.json") == BGIScriptRepositoryWebBridge.notFoundPayload)
        #expect(fixture.bridge.filePayload(forRepositoryPath: "js/demo/secret.exe") == BGIScriptRepositoryWebBridge.notFoundPayload)
        #expect(fixture.bridge.mimeType(forExtension: ".webp") == "image/webp")
        #expect(fixture.bridge.mimeType(forExtension: "unknown") == "application/octet-stream")
    }

    @Test("Web bridge returns subscribed paths JSON and imports BetterGI script URI")
    func webBridgeReturnsSubscribedPathsAndImportsURI() throws {
        let fixture = try WebBridgeFixture()
        defer { fixture.cleanup() }

        try fixture.writeRepositoryIndex(hasUpdate: nil)
        try fixture.writeRepositoryFile("console.log('demo');\n", relativePath: "repo/js/demo/index.js")
        try fixture.writeRepositoryFile("{\"name\":\"demo\"}\n", relativePath: "repo/pathing/demo/path.json")
        try fixture.writeRepositoryFile("combat\n", relativePath: "repo/combat/default.txt")
        try fixture.writeRepositoryFile("tcg\n", relativePath: "repo/tcg/default.txt")

        #expect(fixture.bridge.subscribedScriptPathsJSON() == "[]")

        let importURI = betterGIImportURI(paths: ["js/demo"])
        let result = try fixture.bridge.importURI(importURI)

        #expect(result.checkoutResults.map(\.sourcePath) == ["js/demo"])
        #expect(fixture.bridge.subscribedScriptPathsJSON() == "[\"js\"]")
        #expect(try String(
            contentsOf: fixture.runtimeStore.userURL.appendingPathComponent("JsScript/demo/index.js"),
            encoding: .utf8
        ) == "console.log('demo');\n")
    }
}

private final class WebBridgeFixture {
    let tempRoot: URL
    let runtimeStore: BGIRuntimeResourceStore
    let updater: BGIScriptRepositoryUpdater
    let subscriptionStore: BGIScriptSubscriptionStore
    let bridge: BGIScriptRepositoryWebBridge

    init() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-web-bridge-test-\(UUID().uuidString)", isDirectory: true)
        runtimeStore = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        try runtimeStore.createDirectorySkeleton()
        updater = BGIScriptRepositoryUpdater(store: runtimeStore)
        subscriptionStore = BGIScriptSubscriptionStore(store: runtimeStore)
        bridge = BGIScriptRepositoryWebBridge(
            updater: updater,
            subscriptionStore: subscriptionStore
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func writeRepositoryIndex(hasUpdate: Bool?) throws {
        try writeRepositoryFile(repositoryIndexJSON(hasUpdate: hasUpdate), relativePath: "repo.json")
        try FileManager.default.createDirectory(
            at: updater.repositoryContentURL.appendingPathComponent("js", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: updater.repositoryContentURL.appendingPathComponent("pathing", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: updater.repositoryContentURL.appendingPathComponent("combat", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: updater.repositoryContentURL.appendingPathComponent("tcg", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func writeUpdatedRepositoryIndex(hasUpdate: Bool?) throws {
        try writeRepositoryFile(repositoryIndexJSON(hasUpdate: hasUpdate), relativePath: "repo_updated.json")
    }

    func writeRepositoryFile(_ content: String, relativePath: String) throws {
        let url = updater.centerRepositoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeRepositoryFile(_ data: Data, relativePath: String) throws {
        let url = updater.centerRepositoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

private func repositoryIndexJSON(hasUpdate: Bool?) -> String {
    var nested: [String: Any] = [
        "name": "nested",
        "type": "directory"
    ]
    if let hasUpdate {
        nested["hasUpdate"] = hasUpdate
    }

    var demo: [String: Any] = [
        "name": "demo",
        "type": "directory",
        "lastUpdated": "2026-01-01 00:00:00",
        "children": [nested]
    ]
    if let hasUpdate {
        demo["hasUpdate"] = hasUpdate
    }

    var js: [String: Any] = [
        "name": "js",
        "type": "directory",
        "lastUpdated": "2026-01-01 00:00:00",
        "children": [demo]
    ]
    if let hasUpdate {
        js["hasUpdate"] = hasUpdate
    }

    let object: [String: Any] = [
        "time": "20260701150000",
        "url": "https://github.com/babalae/bettergi-scripts-list/archive/refs/heads/main.zip",
        "file": "repo.json",
        "indexes": [
            js,
            ["name": "pathing", "type": "directory", "children": [["name": "demo", "type": "directory"]]],
            ["name": "combat", "type": "directory"],
            ["name": "tcg", "type": "directory"]
        ]
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
    return String(data: data, encoding: .utf8)!
}

private func repoWebBridgeNode(path: [String], json: String) throws -> [String: Any] {
    let data = try #require(json.data(using: .utf8))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    var nodes = try #require(object["indexes"] as? [[String: Any]])
    var matched: [String: Any]?

    for name in path {
        matched = nodes.first { ($0["name"] as? String) == name }
        guard let matchedNode = matched else { break }
        nodes = matchedNode["children"] as? [[String: Any]] ?? []
    }

    return try #require(matched)
}

private func betterGIImportURI(paths: [String]) -> String {
    let data = try! JSONEncoder().encode(paths)
    let json = String(data: data, encoding: .utf8)!
    let encodedJSON = json.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? json
    let base64 = Data(encodedJSON.utf8).base64EncodedString()
    return "bettergi://script?import=\(base64)"
}
