import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI script repository update markers")
struct BGIScriptRepositoryUpdateMarkerTests {
    @Test("Repository overlap uses directory overlap coefficient")
    func repositoryOverlapUsesDirectoryOverlapCoefficient() {
        let generator = BGIScriptRepositoryUpdateMarkerGenerator()

        let oldJSON = repoJSON([
            directoryNode("pathing", children: [directoryNode("demo")]),
            directoryNode("js", children: [directoryNode("old")])
        ])
        let newJSON = repoJSON([
            directoryNode("pathing", children: [directoryNode("demo")]),
            directoryNode("js", children: [directoryNode("new")])
        ])

        #expect(generator.calculateOverlapRatio(oldJSON: oldJSON, newJSON: newJSON) == 0.75)
        #expect(generator.calculateOverlapRatio(
            oldJSON: repoJSON([directoryNode("pathing", children: [directoryNode("demo")])]),
            newJSON: repoJSON([directoryNode("combat", children: [directoryNode("demo")])])
        ) == 0.0)
    }

    @Test("Update marker flags newer, new, and previously pending leaf nodes")
    func updateMarkerFlagsNewerNewAndPreviouslyPendingNodes() throws {
        let generator = BGIScriptRepositoryUpdateMarkerGenerator()
        let oldJSON = repoJSON([
            directoryNode(
                "js",
                lastUpdated: "2026-01-01 00:00:00",
                children: [
                    directoryNode("demo", lastUpdated: "2026-01-01 00:00:00"),
                    directoryNode("pending", lastUpdated: "2026-01-01 00:00:00", hasUpdate: true)
                ]
            )
        ])
        let newJSON = repoJSON([
            directoryNode(
                "js",
                lastUpdated: "2026-01-01 00:00:00",
                children: [
                    directoryNode("demo", lastUpdated: "2026-02-01 00:00:00"),
                    directoryNode("pending", lastUpdated: "2026-01-01 00:00:00"),
                    directoryNode("fresh", lastUpdated: "2026-03-01 00:00:00")
                ]
            )
        ])

        let result = generator.generate(previousJSON: oldJSON, newJSON: newJSON)
        let indexes = try repoIndexes(from: result.content)
        let js = try #require(indexes.first)
        let children = try #require(js["children"] as? [[String: Any]])

        #expect(result.overlapRatio == 1.0)
        #expect(js["hasUpdate"] as? Bool == true)
        #expect(js["lastUpdated"] as? String == "2026-03-01 00:00:00")
        #expect(children.first(where: { ($0["name"] as? String) == "demo" })?["hasUpdate"] as? Bool == true)
        #expect(children.first(where: { ($0["name"] as? String) == "pending" })?["hasUpdate"] as? Bool == true)
        #expect(children.first(where: { ($0["name"] as? String) == "fresh" })?["hasUpdate"] as? Bool == true)
    }

    @Test("Update marker does not inherit markers when repository overlap is low")
    func updateMarkerDoesNotInheritMarkersWhenOverlapIsLow() throws {
        let generator = BGIScriptRepositoryUpdateMarkerGenerator()
        let oldJSON = repoJSON([
            directoryNode("pathing", children: [
                directoryNode("old", lastUpdated: "2026-01-01 00:00:00", hasUpdate: true)
            ])
        ])
        let newJSON = repoJSON([
            directoryNode("combat", children: [
                directoryNode("new", lastUpdated: "2026-01-01 00:00:00")
            ])
        ])

        let result = generator.generate(previousJSON: oldJSON, newJSON: newJSON)
        let indexes = try repoIndexes(from: result.content)
        let combat = try #require(indexes.first)
        let children = try #require(combat["children"] as? [[String: Any]])

        #expect(result.overlapRatio == 0.0)
        #expect(result.inheritedPreviousMarkers == false)
        #expect(combat["hasUpdate"] == nil)
        #expect(children.first?["hasUpdate"] == nil)
    }

    @Test("Script repository updater writes repo_updated.json after clone and fetch")
    func scriptRepositoryUpdaterWritesRepoUpdatedJSONAfterCloneAndFetch() async throws {
        try requireMarkerGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-marker-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createMarkerFixtureRepository(
            at: sourceRepositoryURL,
            demoUpdated: "2026-01-01 00:00:00",
            helperUpdated: nil
        )

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        _ = try await updater.ensureCenterRepository(channels: [markerLocalChannel(sourceRepositoryURL)])

        #expect(FileManager.default.fileExists(atPath: updater.repoUpdatedJSONURL.path))
        var indexes = try repoIndexes(from: try String(contentsOf: updater.repoUpdatedJSONURL, encoding: .utf8))
        var js = try #require(indexes.first(where: { ($0["name"] as? String) == "js" }))
        #expect(js["hasUpdate"] == nil)

        try updateMarkerFixtureRepository(
            at: sourceRepositoryURL,
            demoUpdated: "2026-02-01 00:00:00",
            helperUpdated: "2026-03-01 00:00:00"
        )
        _ = try await updater.ensureCenterRepository(channels: [markerLocalChannel(sourceRepositoryURL)])

        indexes = try repoIndexes(from: try String(contentsOf: updater.repoUpdatedJSONURL, encoding: .utf8))
        js = try #require(indexes.first(where: { ($0["name"] as? String) == "js" }))
        let children = try #require(js["children"] as? [[String: Any]])

        #expect(js["hasUpdate"] as? Bool == true)
        #expect(js["lastUpdated"] as? String == "2026-03-01 00:00:00")
        #expect(children.first(where: { ($0["name"] as? String) == "demo" })?["hasUpdate"] as? Bool == true)
        #expect(children.first(where: { ($0["name"] as? String) == "helper" })?["hasUpdate"] as? Bool == true)
    }
}

private func repoJSON(_ indexes: [[String: Any]]) -> String {
    let object: [String: Any] = [
        "time": "20260701143000",
        "url": "https://github.com/babalae/bettergi-scripts-list/archive/refs/heads/main.zip",
        "file": "repo.json",
        "indexes": indexes
    ]
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
    return String(data: data, encoding: .utf8)!
}

private func directoryNode(
    _ name: String,
    lastUpdated: String? = nil,
    hasUpdate: Bool? = nil,
    children: [[String: Any]] = []
) -> [String: Any] {
    var node: [String: Any] = [
        "name": name,
        "type": "directory"
    ]
    if let lastUpdated {
        node["lastUpdated"] = lastUpdated
    }
    if let hasUpdate {
        node["hasUpdate"] = hasUpdate
    }
    if !children.isEmpty {
        node["children"] = children
    }
    return node
}

private func repoIndexes(from content: String) throws -> [[String: Any]] {
    let data = try #require(content.data(using: .utf8))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    return try #require(object["indexes"] as? [[String: Any]])
}

private func requireMarkerGit() throws {
    let gitPath = "/usr/bin/git"
    if !FileManager.default.isExecutableFile(atPath: gitPath) {
        throw BGIScriptRepositoryUpdaterError.gitUnavailable(gitPath)
    }
}

private func markerLocalChannel(_ repositoryURL: URL) -> BGIScriptRepositoryChannel {
    BGIScriptRepositoryChannel(id: "Local", name: "Local", url: repositoryURL)
}

private func createMarkerFixtureRepository(
    at repositoryURL: URL,
    demoUpdated: String,
    helperUpdated: String?
) throws {
    try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
    try writeMarkerFixtureContents(at: repositoryURL, demoUpdated: demoUpdated, helperUpdated: helperUpdated)

    try runMarkerGit(["init", repositoryURL.path])
    try runMarkerGit(["-C", repositoryURL.path, "checkout", "-B", "release"])
    try runMarkerGit(["-C", repositoryURL.path, "config", "user.email", "bettergi-mac-tests@example.invalid"])
    try runMarkerGit(["-C", repositoryURL.path, "config", "user.name", "betterGI-mac Tests"])
    try runMarkerGit(["-C", repositoryURL.path, "add", "."])
    try runMarkerGit(["-C", repositoryURL.path, "commit", "-m", "initial marker fixture"])
}

private func updateMarkerFixtureRepository(
    at repositoryURL: URL,
    demoUpdated: String,
    helperUpdated: String?
) throws {
    try writeMarkerFixtureContents(at: repositoryURL, demoUpdated: demoUpdated, helperUpdated: helperUpdated)
    try runMarkerGit(["-C", repositoryURL.path, "add", "."])
    try runMarkerGit(["-C", repositoryURL.path, "commit", "-m", "update marker fixture"])
}

private func writeMarkerFixtureContents(
    at repositoryURL: URL,
    demoUpdated: String,
    helperUpdated: String?
) throws {
    var jsChildren = [directoryNode("demo", lastUpdated: demoUpdated)]
    if let helperUpdated {
        jsChildren.append(directoryNode("helper", lastUpdated: helperUpdated))
    }

    try writeMarkerFixtureFile(
        repoJSON([
            directoryNode("js", lastUpdated: "2026-01-01 00:00:00", children: jsChildren),
            directoryNode("pathing", children: [directoryNode("demo")]),
            directoryNode("combat"),
            directoryNode("tcg")
        ]),
        relativePath: "repo.json",
        under: repositoryURL
    )
    try writeMarkerFixtureFile("console.log('demo');\n", relativePath: "repo/js/demo/index.js", under: repositoryURL)
    if helperUpdated != nil {
        try writeMarkerFixtureFile("console.log('helper');\n", relativePath: "repo/js/helper/index.js", under: repositoryURL)
    }
    try writeMarkerFixtureFile("{\"name\":\"demo\"}\n", relativePath: "repo/pathing/demo/path.json", under: repositoryURL)
    try writeMarkerFixtureFile("combat\n", relativePath: "repo/combat/default.txt", under: repositoryURL)
    try writeMarkerFixtureFile("tcg\n", relativePath: "repo/tcg/default.txt", under: repositoryURL)
}

private func writeMarkerFixtureFile(_ content: String, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func runMarkerGit(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments

    let stderrPipe = Pipe()
    process.standardError = stderrPipe
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw BGIScriptRepositoryUpdaterError.gitCommandFailed(
            arguments: arguments,
            exitCode: process.terminationStatus,
            stderr: stderr
        )
    }
}
