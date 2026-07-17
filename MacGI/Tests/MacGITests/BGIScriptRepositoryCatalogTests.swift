import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI script repository catalog")
struct BGIScriptRepositoryCatalogTests {
    @Test("Repository index parser flattens BetterGI repo.json trees")
    func repositoryIndexParserFlattensBetterGIRepoJsonTrees() throws {
        let data = Data("""
        {
          "time": "20260630201352",
          "url": "https://github.com/babalae/bettergi-scripts-list/archive/refs/heads/main.zip",
          "file": "repo.json",
          "indexes": [
            {
              "name": "pathing",
              "type": "directory",
              "children": [
                {
                  "name": "地方特产",
                  "type": "directory",
                  "children": [
                    {
                      "name": "星螺.json",
                      "type": "file",
                      "version": "1.0",
                      "author": "Example",
                      "authors": [{"name": "Example", "link": "https://example.invalid"}],
                      "description": "路线信息",
                      "tags": ["bgi>=0.45.0", "采集"],
                      "lastUpdated": "2026-04-15 19:52:58",
                      "hasUpdate": true
                    }
                  ]
                }
              ]
            },
            {"name": "js", "type": "directory", "children": []}
          ]
        }
        """.utf8)

        let index = try JSONDecoder().decode(BGIScriptRepositoryIndex.self, from: data)
        let entries = index.flattenedEntries()
        let filesOnly = index.flattenedEntries(includeDirectories: false)

        #expect(index.time == "20260630201352")
        #expect(entries.map(\.path) == ["pathing", "pathing/地方特产", "pathing/地方特产/星螺.json", "js"])
        #expect(filesOnly.map(\.path) == ["pathing/地方特产/星螺.json"])
        #expect(filesOnly[0].root == .pathing)
        #expect(filesOnly[0].authors == [BGIScriptAuthor(name: "Example", link: "https://example.invalid")])
        #expect(filesOnly[0].tags == ["bgi>=0.45.0", "采集"])
        #expect(filesOnly[0].hasUpdate)
    }

    @Test("JS manifest parser accepts upstream snake case fields and settings")
    func jsManifestParserAcceptsUpstreamSnakeCaseFieldsAndSettings() throws {
        let manifest = try JSONDecoder().decode(BGIJSScriptManifest.self, from: Data("""
        {
          "manifest_version": 1,
          "name": "莉奈娅挖矿一条龙",
          "version": "0.2.5",
          "bgi_version": "0.61.0",
          "description": "不分矿种，稳定刷新即挖",
          "authors": [{"name": "躁动的氨气", "links": "https://github.com/zaodonganqi"}],
          "settings_ui": "settings.json",
          "main": "main.js",
          "saved_files": ["WebView2Data", "local/refresh_records.json"],
          "library": [".", "utils"],
          "http_allowed_urls": ["https://example.invalid"],
          "dependencies": [],
          "tags": ["mining"]
        }
        """.utf8))
        let settings = try JSONDecoder().decode([BGIJSScriptSettingItem].self, from: Data("""
        [
          {"name": "excludeRegions", "type": "multi-checkbox", "label": "跳过以下地区", "options": ["挪德卡莱", "纳塔"]},
          {"type": "separator"},
          {"name": "skipBattleRoutes", "type": "checkbox", "default": false, "label": "跳过战斗点位"}
        ]
        """.utf8))

        #expect(manifest.name == "莉奈娅挖矿一条龙")
        #expect(manifest.bgiVersion == "0.61.0")
        #expect(manifest.authors == [BGIScriptAuthor(name: "躁动的氨气", link: "https://github.com/zaodonganqi")])
        #expect(manifest.settingsUI == "settings.json")
        #expect(manifest.savedFiles == ["WebView2Data", "local/refresh_records.json"])
        #expect(manifest.library == [".", "utils"])
        #expect(manifest.httpAllowedUrls == ["https://example.invalid"])
        #expect(settings[0].type == "multi-checkbox")
        #expect(settings[0].options == ["挪德卡莱", "纳塔"])
        #expect(settings[1].type == "separator")
        #expect(settings[2].defaultValue == .bool(false))
    }

    @Test("Catalog loader reads JS projects and records invalid project issues")
    func catalogLoaderReadsJSProjectsAndRecordsInvalidProjectIssues() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-catalog-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let repositoryContentURL = tempRoot.appendingPathComponent("repo", isDirectory: true)
        try writeCatalogFixtureFile(
            """
            {
              "manifest_version": 1,
              "name": "Valid Script",
              "version": "1.0.0",
              "description": "fixture",
              "authors": [{"name": "A", "link": "https://example.invalid"}],
              "settings_ui": "settings.json",
              "main": "main.js",
              "saved_files": ["local/state.json"]
            }
            """,
            relativePath: "js/valid/manifest.json",
            under: repositoryContentURL
        )
        try writeCatalogFixtureFile("console.log('valid');\n", relativePath: "js/valid/main.js", under: repositoryContentURL)
        try writeCatalogFixtureFile(
            """
            [
              {"name": "enabled", "type": "checkbox", "default": true, "label": "Enabled"}
            ]
            """,
            relativePath: "js/valid/settings.json",
            under: repositoryContentURL
        )
        try writeCatalogFixtureFile(
            """
            {"name": "Broken Script", "version": "1.0.0", "main": "missing.js"}
            """,
            relativePath: "js/broken/manifest.json",
            under: repositoryContentURL
        )

        let result = try BGIScriptRepositoryCatalogLoader().loadJSScriptProjects(from: repositoryContentURL)

        #expect(result.projects.map(\.folderName) == ["valid"])
        #expect(result.projects[0].manifest.name == "Valid Script")
        #expect(result.projects[0].settings.map(\.name) == ["enabled"])
        #expect(result.projects[0].settings[0].defaultValue == .bool(true))
        #expect(result.projects[0].mainScriptURL.lastPathComponent == "main.js")
        #expect(result.issues.count == 1)
        #expect(result.issues[0].path == "js/broken")
        #expect(result.issues[0].message.contains("missing.js"))
    }

    @Test("Script repository updater exposes loaded index and JS projects")
    func scriptRepositoryUpdaterExposesLoadedIndexAndJSProjects() async throws {
        try requireCatalogGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-updater-catalog-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createCatalogFixtureScriptRepository(at: sourceRepositoryURL)

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        _ = try await updater.ensureCenterRepository(channels: [localCatalogScriptChannel(sourceRepositoryURL)])

        let index = try updater.loadRepositoryIndex()
        let projects = try updater.loadJSScriptProjects()

        #expect(index.flattenedEntries(includeDirectories: false).map(\.path).contains("js/demo/index.js"))
        #expect(projects.projects.map(\.folderName) == ["demo"])
        #expect(projects.projects[0].manifest.name == "Demo catalog")
        #expect(projects.projects[0].manifest.main == "index.js")
        #expect(projects.issues.isEmpty)
    }

    @Test("Real cloned script repository catalog parses when present")
    func realClonedScriptRepositoryCatalogParsesWhenPresent() throws {
        let store = BGIRuntimeResourceStore.defaultStore()
        let repositoryURL = store.reposURL.appendingPathComponent("bettergi-scripts-list", isDirectory: true)
        let repositoryContentURL = repositoryURL.appendingPathComponent("repo", isDirectory: true)
        guard FileManager.default.fileExists(atPath: repositoryURL.appendingPathComponent("repo.json").path),
              FileManager.default.fileExists(atPath: repositoryContentURL.appendingPathComponent("js").path) else {
            return
        }

        let loader = BGIScriptRepositoryCatalogLoader()
        let index = try loader.loadIndex(from: repositoryURL)
        let entries = index.flattenedEntries()
        let projects = try loader.loadJSScriptProjects(from: repositoryContentURL)

        #expect(entries.contains { $0.root == .js })
        #expect(entries.contains { $0.root == .pathing })
        #expect(entries.contains { $0.root == .combat })
        #expect(entries.contains { $0.root == .tcg })
        #expect(projects.projects.count >= 100)
    }
}

private func writeCatalogFixtureFile(_ content: String, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func requireCatalogGit() throws {
    let gitPath = "/usr/bin/git"
    if !FileManager.default.isExecutableFile(atPath: gitPath) {
        throw BGIScriptRepositoryUpdaterError.gitUnavailable(gitPath)
    }
}

private func localCatalogScriptChannel(_ repositoryURL: URL) -> BGIScriptRepositoryChannel {
    BGIScriptRepositoryChannel(id: "Local", name: "Local", url: repositoryURL)
}

private func createCatalogFixtureScriptRepository(at repositoryURL: URL) throws {
    try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
    try writeCatalogFixtureFile(
        """
        {
          "time": "20260701000000",
          "file": "repo.json",
          "indexes": [
            {
              "name": "js",
              "type": "directory",
              "children": [
                {
                  "name": "demo",
                  "type": "directory",
                  "children": [
                    {"name": "index.js", "type": "file", "version": "1.0.0"}
                  ]
                }
              ]
            },
            {"name": "pathing", "type": "directory", "children": [{"name": "demo.json", "type": "file"}]},
            {"name": "combat", "type": "directory", "children": [{"name": "default.txt", "type": "file"}]},
            {"name": "tcg", "type": "directory", "children": [{"name": "default.txt", "type": "file"}]}
          ]
        }
        """,
        relativePath: "repo.json",
        under: repositoryURL
    )
    try writeCatalogFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "Demo catalog",
          "version": "1.0.0",
          "main": "index.js"
        }
        """,
        relativePath: "repo/js/demo/manifest.json",
        under: repositoryURL
    )
    try writeCatalogFixtureFile("console.log('catalog');\n", relativePath: "repo/js/demo/index.js", under: repositoryURL)
    try writeCatalogFixtureFile("{}\n", relativePath: "repo/pathing/demo.json", under: repositoryURL)
    try writeCatalogFixtureFile("combat\n", relativePath: "repo/combat/default.txt", under: repositoryURL)
    try writeCatalogFixtureFile("tcg\n", relativePath: "repo/tcg/default.txt", under: repositoryURL)

    try runCatalogGit(["init", repositoryURL.path])
    try runCatalogGit(["-C", repositoryURL.path, "checkout", "-B", "release"])
    try runCatalogGit(["-C", repositoryURL.path, "config", "user.email", "bettergi-mac-tests@example.invalid"])
    try runCatalogGit(["-C", repositoryURL.path, "config", "user.name", "betterGI-mac Tests"])
    try runCatalogGit(["-C", repositoryURL.path, "add", "."])
    try runCatalogGit(["-C", repositoryURL.path, "commit", "-m", "catalog fixture"])
}

private func runCatalogGit(_ arguments: [String]) throws {
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
