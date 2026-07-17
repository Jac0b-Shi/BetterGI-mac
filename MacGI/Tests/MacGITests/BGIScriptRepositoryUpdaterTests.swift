import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI script repository updater")
struct BGIScriptRepositoryUpdaterTests {
    @Test("Default script repository channels and path mappings mirror upstream BetterGI")
    func defaultScriptRepositoryChannelsAndPathMappingsMirrorUpstreamBetterGI() {
        #expect(BGIScriptRepositoryChannel.upstreamDefaults.map(\.name) == ["CNB", "GitCode", "GitHub"])
        #expect(BGIScriptRepositoryChannel.upstreamDefaults.map(\.url.absoluteString) == [
            "https://cnb.cool/bettergi/bettergi-scripts-list",
            "https://gitcode.com/huiyadanli/bettergi-scripts-list",
            "https://github.com/babalae/bettergi-scripts-list"
        ])
        #expect(BGIScriptRepositoryPathMapping.upstreamDefaults == [
            BGIScriptRepositoryPathMapping(repositoryRoot: "pathing", userDirectoryName: "AutoPathing"),
            BGIScriptRepositoryPathMapping(repositoryRoot: "js", userDirectoryName: "JsScript"),
            BGIScriptRepositoryPathMapping(repositoryRoot: "combat", userDirectoryName: "AutoFight"),
            BGIScriptRepositoryPathMapping(repositoryRoot: "tcg", userDirectoryName: "AutoGeniusInvokation")
        ])
    }

    @Test("Script repository updater clones the release branch and validates repo layout")
    func scriptRepositoryUpdaterClonesReleaseBranchAndValidatesRepoLayout() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-clone-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createFixtureScriptRepository(at: sourceRepositoryURL, marker: "initial")

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        let result = try await updater.ensureCenterRepository(channels: [localScriptChannel(sourceRepositoryURL)])

        #expect(result.status == .cloned)
        #expect(result.channel.name == "Local")
        #expect(FileManager.default.fileExists(atPath: store.url(forAssetPath: "Repos/bettergi-scripts-list/repo.json").path))
        #expect(try updater.readRepositoryFile("js/demo/index.js") == "console.log('initial');\n")
    }

    @Test("Script repository updater fetches release branch changes into an existing clone")
    func scriptRepositoryUpdaterFetchesReleaseBranchChangesIntoExistingClone() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-update-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createFixtureScriptRepository(at: sourceRepositoryURL, marker: "v1")

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        let channel = localScriptChannel(sourceRepositoryURL)

        let firstResult = try await updater.ensureCenterRepository(channels: [channel])
        try updateFixtureScriptRepository(at: sourceRepositoryURL, marker: "v2")
        let secondResult = try await updater.ensureCenterRepository(channels: [channel])

        #expect(firstResult.status == .cloned)
        #expect(secondResult.status == .updated)
        #expect(try updater.readRepositoryFile("js/demo/index.js") == "console.log('v2');\n")
    }

    @Test("Script repository updater tries later mirrors after clone failure")
    func scriptRepositoryUpdaterTriesLaterMirrorsAfterCloneFailure() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-mirror-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createFixtureScriptRepository(at: sourceRepositoryURL, marker: "mirror")

        let missingRepositoryURL = tempRoot.appendingPathComponent("MissingRepo", isDirectory: true)
        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        let result = try await updater.ensureCenterRepository(channels: [
            BGIScriptRepositoryChannel(id: "missing", name: "Missing", url: missingRepositoryURL),
            localScriptChannel(sourceRepositoryURL)
        ])

        #expect(result.status == .cloned)
        #expect(result.channel.name == "Local")
        #expect(result.failureMessages.count == 1)
        #expect(try updater.readRepositoryFile("js/demo/index.js") == "console.log('mirror');\n")
    }

    @Test("Script repository updater checks out subscribed paths into BetterGI user folders")
    func scriptRepositoryUpdaterChecksOutSubscribedPathsIntoBetterGIUserFolders() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-checkout-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createFixtureScriptRepository(at: sourceRepositoryURL, marker: "checkout")

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        _ = try await updater.ensureCenterRepository(channels: [localScriptChannel(sourceRepositoryURL)])

        let results = try updater.checkout(paths: [
            "js/demo",
            "pathing/demo",
            "combat/default.txt",
            "tcg/default.txt"
        ])

        #expect(results.map(\.sourcePath) == ["js/demo", "pathing/demo", "combat/default.txt", "tcg/default.txt"])
        #expect(try String(contentsOf: store.userURL.appendingPathComponent("JsScript/demo/index.js"), encoding: .utf8) == "console.log('checkout');\n")
        #expect(try String(contentsOf: store.userURL.appendingPathComponent("AutoPathing/demo/path.json"), encoding: .utf8) == "{\"name\":\"checkout\"}\n")
        #expect(try String(contentsOf: store.userURL.appendingPathComponent("AutoFight/default.txt"), encoding: .utf8) == "combat checkout\n")
        #expect(try String(contentsOf: store.userURL.appendingPathComponent("AutoGeniusInvokation/default.txt"), encoding: .utf8) == "tcg checkout\n")
    }

    @Test("Script repository updater preserves JS saved_files and resolves packages dependencies")
    func scriptRepositoryUpdaterPreservesJSSavedFilesAndResolvesPackagesDependencies() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-js-install-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createJSScriptInstallFixtureRepository(at: sourceRepositoryURL, marker: "v1")

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        let channel = localScriptChannel(sourceRepositoryURL)
        _ = try await updater.ensureCenterRepository(channels: [channel])

        _ = try updater.checkout(paths: ["js/demo"])
        let userScriptURL = store.userURL.appendingPathComponent("JsScript/demo", isDirectory: true)
        try writeFixtureFile("user state\n", relativePath: "data/state.json", under: userScriptURL)
        try writeFixtureFile("cached\n", relativePath: "cache/keep.txt", under: userScriptURL)
        try FileManager.default.createDirectory(
            at: userScriptURL.appendingPathComponent("cache/empty", isDirectory: true),
            withIntermediateDirectories: true
        )
        try writeFixtureFile("remove me\n", relativePath: "transient.txt", under: userScriptURL)

        try updateJSScriptInstallFixtureRepository(at: sourceRepositoryURL, marker: "v2")
        _ = try await updater.ensureCenterRepository(channels: [channel])
        let results = try updater.checkout(paths: ["js/demo"])

        #expect(results.map(\.sourcePath) == ["js/demo"])
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("main.js"), encoding: .utf8).contains("v2"))
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("data/state.json"), encoding: .utf8) == "user state\n")
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("cache/keep.txt"), encoding: .utf8) == "cached\n")
        #expect(FileManager.default.fileExists(atPath: userScriptURL.appendingPathComponent("cache/empty").path))
        #expect(FileManager.default.fileExists(atPath: userScriptURL.appendingPathComponent("transient.txt").path) == false)
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("packages/utils/tool.js"), encoding: .utf8).contains("tool"))
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("packages/utils/extra.js"), encoding: .utf8).contains("extra"))
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("packages/widgets/index.js"), encoding: .utf8).contains("widget"))
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("packages/widgets/inner.js"), encoding: .utf8).contains("inner"))
    }

    @Test("Script repository updater preserves saved_files directory symlinks")
    func scriptRepositoryUpdaterPreservesSavedFilesDirectorySymlinks() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-saved-files-symlink-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createJSScriptInstallFixtureRepository(at: sourceRepositoryURL, marker: "v1")

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        let channel = localScriptChannel(sourceRepositoryURL)
        _ = try await updater.ensureCenterRepository(channels: [channel])

        _ = try updater.checkout(paths: ["js/demo"])
        let userScriptURL = store.userURL.appendingPathComponent("JsScript/demo", isDirectory: true)
        let externalCacheURL = tempRoot.appendingPathComponent("External/cache", isDirectory: true)
        let cacheSymlinkURL = userScriptURL.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.removeItem(at: cacheSymlinkURL)
        try FileManager.default.createDirectory(at: externalCacheURL, withIntermediateDirectories: true)
        try "external cache\n".write(
            to: externalCacheURL.appendingPathComponent("keep.txt"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(at: cacheSymlinkURL, withDestinationURL: externalCacheURL)
        try writeFixtureFile("remove me\n", relativePath: "transient.txt", under: userScriptURL)

        try updateJSScriptInstallFixtureRepository(at: sourceRepositoryURL, marker: "v2")
        _ = try await updater.ensureCenterRepository(channels: [channel])
        _ = try updater.checkout(paths: ["js/demo"])

        #expect(try isSymbolicLink(at: cacheSymlinkURL))
        #expect(try String(contentsOf: externalCacheURL.appendingPathComponent("keep.txt"), encoding: .utf8) == "external cache\n")
        #expect(FileManager.default.fileExists(atPath: userScriptURL.appendingPathComponent("transient.txt").path) == false)
        #expect(try String(contentsOf: userScriptURL.appendingPathComponent("main.js"), encoding: .utf8).contains("v2"))
    }

    @Test("Script repository updater preserves symlinked user script folders")
    func scriptRepositoryUpdaterPreservesSymlinkedUserScriptFolders() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-symlink-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createFixtureScriptRepository(at: sourceRepositoryURL, marker: "symlink")

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        _ = try await updater.ensureCenterRepository(channels: [localScriptChannel(sourceRepositoryURL)])

        let externalScriptURL = tempRoot.appendingPathComponent("External/User/JsScript", isDirectory: true)
        let symlinkedScriptURL = store.userURL.appendingPathComponent("JsScript", isDirectory: true)
        try FileManager.default.removeItem(at: symlinkedScriptURL)
        try FileManager.default.createDirectory(at: externalScriptURL, withIntermediateDirectories: true)
        try "stale\n".write(to: externalScriptURL.appendingPathComponent("old.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlinkedScriptURL, withDestinationURL: externalScriptURL)

        let results = try updater.checkout(paths: ["js"])

        #expect(results.map(\.sourcePath) == ["js"])
        #expect(try isSymbolicLink(at: symlinkedScriptURL))
        #expect(FileManager.default.fileExists(atPath: externalScriptURL.appendingPathComponent("old.txt").path) == false)
        #expect(try String(contentsOf: externalScriptURL.appendingPathComponent("demo/index.js"), encoding: .utf8) == "console.log('symlink');\n")
    }

    @Test("Script repository updater follows symlinked Application Support roots")
    func scriptRepositoryUpdaterFollowsSymlinkedApplicationSupportRoots() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-root-symlink-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createFixtureScriptRepository(at: sourceRepositoryURL, marker: "root-symlink")

        let externalRoot = tempRoot.appendingPathComponent("Volumes/Data/Library/Application Support/betterGI-mac", isDirectory: true)
        let linkedRoot = tempRoot.appendingPathComponent("Home/Library/Application Support/betterGI-mac", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: externalRoot)

        let store = BGIRuntimeResourceStore(rootURL: linkedRoot)
        let updater = BGIScriptRepositoryUpdater(store: store)
        _ = try await updater.ensureCenterRepository(channels: [localScriptChannel(sourceRepositoryURL)])
        let results = try updater.checkout(paths: ["js/demo"])

        #expect(results.map(\.sourcePath) == ["js/demo"])
        #expect(try isSymbolicLink(at: linkedRoot))
        #expect(FileManager.default.fileExists(atPath: externalRoot.appendingPathComponent("Repos/bettergi-scripts-list/repo.json").path))
        #expect(try String(contentsOf: externalRoot.appendingPathComponent("User/JsScript/demo/index.js"), encoding: .utf8) == "console.log('root-symlink');\n")
    }

    @Test("Script repository updater rejects unsafe checkout paths")
    func scriptRepositoryUpdaterRejectsUnsafeCheckoutPaths() async throws {
        try requireGit()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-script-unsafe-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sourceRepositoryURL = tempRoot.appendingPathComponent("SourceRepo", isDirectory: true)
        try createFixtureScriptRepository(at: sourceRepositoryURL, marker: "unsafe")

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let updater = BGIScriptRepositoryUpdater(store: store)
        _ = try await updater.ensureCenterRepository(channels: [localScriptChannel(sourceRepositoryURL)])

        do {
            _ = try updater.checkout(paths: ["../outside"])
            Issue.record("Expected unsafe repository path to be rejected")
        } catch let error as BGIScriptRepositoryUpdaterError {
            #expect(error == .unsafeRepositoryPath("../outside"))
        }
    }
}

private func requireGit() throws {
    let gitPath = "/usr/bin/git"
    if !FileManager.default.isExecutableFile(atPath: gitPath) {
        throw BGIScriptRepositoryUpdaterError.gitUnavailable(gitPath)
    }
}

private func localScriptChannel(_ repositoryURL: URL) -> BGIScriptRepositoryChannel {
    BGIScriptRepositoryChannel(
        id: "Local",
        name: "Local",
        url: repositoryURL
    )
}

private func createFixtureScriptRepository(at repositoryURL: URL, marker: String) throws {
    try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
    try writeFixtureFile("repo fixture \(marker)\n", relativePath: "repo.json", under: repositoryURL)
    try writeFixtureFile("console.log('\(marker)');\n", relativePath: "repo/js/demo/index.js", under: repositoryURL)
    try writeFixtureFile("{\"name\":\"\(marker)\"}\n", relativePath: "repo/pathing/demo/path.json", under: repositoryURL)
    try writeFixtureFile("combat \(marker)\n", relativePath: "repo/combat/default.txt", under: repositoryURL)
    try writeFixtureFile("tcg \(marker)\n", relativePath: "repo/tcg/default.txt", under: repositoryURL)

    try runGitFixture(["init", repositoryURL.path])
    try runGitFixture(["-C", repositoryURL.path, "checkout", "-B", "release"])
    try runGitFixture(["-C", repositoryURL.path, "config", "user.email", "bettergi-mac-tests@example.invalid"])
    try runGitFixture(["-C", repositoryURL.path, "config", "user.name", "betterGI-mac Tests"])
    try runGitFixture(["-C", repositoryURL.path, "add", "."])
    try runGitFixture(["-C", repositoryURL.path, "commit", "-m", "initial fixture"])
}

private func updateFixtureScriptRepository(at repositoryURL: URL, marker: String) throws {
    try writeFixtureFile("console.log('\(marker)');\n", relativePath: "repo/js/demo/index.js", under: repositoryURL)
    try runGitFixture(["-C", repositoryURL.path, "add", "."])
    try runGitFixture(["-C", repositoryURL.path, "commit", "-m", "update \(marker)"])
}

private func createJSScriptInstallFixtureRepository(at repositoryURL: URL, marker: String) throws {
    try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
    try writeJSScriptInstallFixtureContents(at: repositoryURL, marker: marker)

    try runGitFixture(["init", repositoryURL.path])
    try runGitFixture(["-C", repositoryURL.path, "checkout", "-B", "release"])
    try runGitFixture(["-C", repositoryURL.path, "config", "user.email", "bettergi-mac-tests@example.invalid"])
    try runGitFixture(["-C", repositoryURL.path, "config", "user.name", "betterGI-mac Tests"])
    try runGitFixture(["-C", repositoryURL.path, "add", "."])
    try runGitFixture(["-C", repositoryURL.path, "commit", "-m", "initial js install fixture"])
}

private func updateJSScriptInstallFixtureRepository(at repositoryURL: URL, marker: String) throws {
    try writeJSScriptInstallFixtureContents(at: repositoryURL, marker: marker)
    try runGitFixture(["-C", repositoryURL.path, "add", "."])
    try runGitFixture(["-C", repositoryURL.path, "commit", "-m", "update js install fixture"])
}

private func writeJSScriptInstallFixtureContents(at repositoryURL: URL, marker: String) throws {
    try writeFixtureFile("repo fixture \(marker)\n", relativePath: "repo.json", under: repositoryURL)
    try writeFixtureFile(
        """
        {
          "manifest_version": 1,
          "name": "Demo",
          "version": "\(marker)",
          "main": "main.js",
          "saved_files": ["data/*.json", "cache/"]
        }
        """,
        relativePath: "repo/js/demo/manifest.json",
        under: repositoryURL
    )
    try writeFixtureFile(
        """
        import { tool } from "../../../packages/utils/tool";
        import { widget } from "../../../packages/widgets";
        log.info(tool());
        log.info(widget());
        log.info('\(marker)');
        """,
        relativePath: "repo/js/demo/main.js",
        under: repositoryURL
    )
    try writeFixtureFile(
        """
        import { extra } from "./extra";
        export function tool() { return `tool ${extra()}`; }
        """,
        relativePath: "packages/utils/tool.js",
        under: repositoryURL
    )
    try writeFixtureFile(
        """
        export function extra() { return "extra"; }
        """,
        relativePath: "packages/utils/extra.js",
        under: repositoryURL
    )
    try writeFixtureFile(
        """
        import { inner } from "./inner";
        export function widget() { return `widget ${inner()}`; }
        """,
        relativePath: "packages/widgets/index.js",
        under: repositoryURL
    )
    try writeFixtureFile(
        """
        export function inner() { return "inner"; }
        """,
        relativePath: "packages/widgets/inner.js",
        under: repositoryURL
    )
    try writeFixtureFile("{\"name\":\"\(marker)\"}\n", relativePath: "repo/pathing/demo/path.json", under: repositoryURL)
    try writeFixtureFile("combat \(marker)\n", relativePath: "repo/combat/default.txt", under: repositoryURL)
    try writeFixtureFile("tcg \(marker)\n", relativePath: "repo/tcg/default.txt", under: repositoryURL)
}

private func writeFixtureFile(_ content: String, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func runGitFixture(_ arguments: [String]) throws {
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

private func isSymbolicLink(at url: URL) throws -> Bool {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return attributes[.type] as? FileAttributeType == .typeSymbolicLink
}
