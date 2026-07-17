import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI script subscription store")
struct BGIScriptSubscriptionStoreTests {
    @Test("Subscription store reads, writes, de-duplicates, and deletes repo scoped files")
    func subscriptionStoreReadsWritesAndDeletesRepoScopedFiles() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-subscription-rw-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let runtimeStore = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        try runtimeStore.createDirectorySkeleton()
        let subscriptionStore = BGIScriptSubscriptionStore(store: runtimeStore)

        try subscriptionStore.write(paths: ["pathing/demo", "js/demo", "js/demo"])

        #expect(subscriptionStore.read() == ["js/demo", "pathing/demo"])
        #expect(FileManager.default.fileExists(atPath: subscriptionStore.subscriptionFileURL().path))

        try "not json".write(to: subscriptionStore.subscriptionFileURL(repoFolderName: "broken"), atomically: true, encoding: .utf8)
        #expect(subscriptionStore.read(repoFolderName: "broken").isEmpty)

        try subscriptionStore.write(paths: [])
        #expect(FileManager.default.fileExists(atPath: subscriptionStore.subscriptionFileURL().path) == false)
    }

    @Test("BetterGI script import URL decodes base64 URL-decoded JSON paths")
    func betterGIImportURLDecodesBase64URLDecodedJSONPaths() throws {
        let pathJSON = #"["js/调试脚本","pathing/demo"]"#
        let urlEncodedJSON = pathJSON.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? pathJSON
        let base64 = Data(urlEncodedJSON.utf8).base64EncodedString()
        var components = URLComponents()
        components.scheme = "bettergi"
        components.host = "script"
        components.queryItems = [URLQueryItem(name: "import", value: base64)]

        let url = try #require(components.url?.absoluteString)
        let request = try BGIScriptImportRequest.decode(fromBetterGIURL: url)

        #expect(request.paths == ["js/调试脚本", "pathing/demo"])
    }

    @Test("Subscription cleanup expands top-level paths and compresses fully subscribed parents")
    func subscriptionCleanupExpandsTopLevelPathsAndCompressesParents() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-subscription-clean-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let runtimeStore = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        try runtimeStore.createDirectorySkeleton()
        let subscriptionStore = BGIScriptSubscriptionStore(store: runtimeStore)
        let index = fixtureRepositoryIndex()

        let expanded = try subscriptionStore.expandedCheckoutPaths(
            for: ["js", "pathing/demo"],
            repositoryIndex: index
        )
        #expect(expanded == ["js/demo", "js/helper", "pathing/demo"])

        try FileManager.default.createDirectory(
            at: runtimeStore.userURL.appendingPathComponent("JsScript/demo", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: runtimeStore.userURL.appendingPathComponent("JsScript/helper", isDirectory: true),
            withIntermediateDirectories: true
        )

        let cleaned = try subscriptionStore.cleanSubscribedPaths(
            ["js/demo", "js/helper"],
            repositoryIndex: index
        )
        #expect(cleaned == ["js"])
        #expect(subscriptionStore.read() == ["js"])

        let cleanedFromStoredParent = try subscriptionStore.cleanSubscribedPaths(repositoryIndex: index)
        #expect(cleanedFromStoredParent == ["js"])
    }

    @Test("Importing top-level subscription checks out direct children and persists compressed subscription")
    func importingTopLevelSubscriptionChecksOutDirectChildren() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-subscription-import-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let runtimeStore = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        try runtimeStore.createDirectorySkeleton()
        try createFixtureCenterRepository(under: runtimeStore)

        let updater = BGIScriptRepositoryUpdater(store: runtimeStore)
        let subscriptionStore = BGIScriptSubscriptionStore(store: runtimeStore)
        let result = try subscriptionStore.importPaths(
            ["js"],
            using: updater,
            repositoryIndex: try updater.loadRepositoryIndex()
        )

        #expect(result.subscribedPaths == ["js"])
        #expect(result.expandedCheckoutPaths == ["js/demo", "js/helper"])
        #expect(result.checkoutResults.map(\.sourcePath) == ["js/demo", "js/helper"])
        #expect(result.cleanedPaths == ["js"])
        #expect(result.issues.isEmpty)
        #expect(try String(
            contentsOf: runtimeStore.userURL.appendingPathComponent("JsScript/demo/index.js"),
            encoding: .utf8
        ) == "console.log('demo');\n")
        #expect(try String(
            contentsOf: runtimeStore.userURL.appendingPathComponent("JsScript/helper/index.js"),
            encoding: .utf8
        ) == "console.log('helper');\n")
        #expect(subscriptionStore.read() == ["js"])
    }

    @Test("Subscription store rejects unsafe and unsupported import paths")
    func subscriptionStoreRejectsUnsafeAndUnsupportedPaths() {
        do {
            _ = try BGIScriptImportRequest.decode(pathJSON: #"["../outside"]"#)
            Issue.record("Expected unsafe path to be rejected")
        } catch let error as BGIScriptSubscriptionError {
            #expect(error == .unsafePath("../outside"))
        } catch {
            Issue.record("Expected BGIScriptSubscriptionError, got \(error)")
        }

        do {
            _ = try BGIScriptImportRequest.decode(pathJSON: #"["unknown/demo"]"#)
            Issue.record("Expected unsupported root to be rejected")
        } catch let error as BGIScriptSubscriptionError {
            #expect(error == .unsupportedRoot("unknown"))
        } catch {
            Issue.record("Expected BGIScriptSubscriptionError, got \(error)")
        }
    }
}

private func fixtureRepositoryIndex() -> BGIScriptRepositoryIndex {
    BGIScriptRepositoryIndex(
        time: "2026-07-01",
        url: nil,
        file: nil,
        indexes: [
            BGIScriptRepositoryIndexNode(
                name: "js",
                type: .directory,
                children: [
                    BGIScriptRepositoryIndexNode(name: "demo", type: .directory),
                    BGIScriptRepositoryIndexNode(name: "helper", type: .directory)
                ]
            ),
            BGIScriptRepositoryIndexNode(
                name: "pathing",
                type: .directory,
                children: [
                    BGIScriptRepositoryIndexNode(name: "demo", type: .directory)
                ]
            ),
            BGIScriptRepositoryIndexNode(name: "combat", type: .directory),
            BGIScriptRepositoryIndexNode(name: "tcg", type: .directory)
        ]
    )
}

private func createFixtureCenterRepository(under runtimeStore: BGIRuntimeResourceStore) throws {
    let repositoryURL = runtimeStore.reposURL.appendingPathComponent("bettergi-scripts-list", isDirectory: true)
    try writeSubscriptionFixtureFile(
        """
        {
          "time": "2026-07-01",
          "indexes": [
            {
              "name": "js",
              "type": "directory",
              "children": [
                { "name": "demo", "type": "directory" },
                { "name": "helper", "type": "directory" }
              ]
            },
            {
              "name": "pathing",
              "type": "directory",
              "children": [
                { "name": "demo", "type": "directory" }
              ]
            },
            { "name": "combat", "type": "directory" },
            { "name": "tcg", "type": "directory" }
          ]
        }
        """,
        relativePath: "repo.json",
        under: repositoryURL
    )
    try writeSubscriptionFixtureFile("console.log('demo');\n", relativePath: "repo/js/demo/index.js", under: repositoryURL)
    try writeSubscriptionFixtureFile("console.log('helper');\n", relativePath: "repo/js/helper/index.js", under: repositoryURL)
    try writeSubscriptionFixtureFile("{\"name\":\"demo\"}\n", relativePath: "repo/pathing/demo/path.json", under: repositoryURL)
    try writeSubscriptionFixtureFile("combat\n", relativePath: "repo/combat/default.txt", under: repositoryURL)
    try writeSubscriptionFixtureFile("tcg\n", relativePath: "repo/tcg/default.txt", under: repositoryURL)
}

private func writeSubscriptionFixtureFile(_ content: String, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
}
