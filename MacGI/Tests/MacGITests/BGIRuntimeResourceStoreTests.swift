import Foundation
@testable import MacGI
import Testing

@Suite("BetterGI runtime resource store")
struct BGIRuntimeResourceStoreTests {
    @Test("First-launch directory skeleton matches porting inventory")
    func firstLaunchDirectorySkeletonMatchesPortingInventory() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-store-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot)
        try store.createDirectorySkeleton()

        for directory in store.requiredDirectories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            #expect(exists)
            #expect(isDirectory.boolValue)
        }

        #expect(store.url(forAssetPath: "Assets/Model/Fish/bgi_fish.onnx").path.hasSuffix("Assets/Model/Fish/bgi_fish.onnx"))
        #expect(store.userURL.lastPathComponent == "User")
        #expect(store.reposURL.lastPathComponent == "Repos")
        #expect(store.downloadCacheURL.path.hasSuffix("Cache/Downloads"))
        #expect(store.modelCacheURL.path.hasSuffix("Cache/Model"))
        #expect(store.mapsURL.path.hasSuffix("Assets/Map"))
    }

    @Test("Runtime resource store follows symlinked Application Support roots")
    func runtimeResourceStoreFollowsSymlinkedApplicationSupportRoots() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-store-symlink-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let externalRoot = tempRoot.appendingPathComponent("External/Application Support/betterGI-mac", isDirectory: true)
        let linkedRoot = tempRoot.appendingPathComponent("Home/Library/Application Support/betterGI-mac", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: externalRoot)

        let store = BGIRuntimeResourceStore(rootURL: linkedRoot)
        try store.createDirectorySkeleton()

        #expect(store.resolvedRootURL.standardizedFileURL == externalRoot.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: externalRoot.appendingPathComponent("User/JsScript").path))
        #expect(FileManager.default.fileExists(atPath: externalRoot.appendingPathComponent("Cache/Downloads").path))
        #expect(store.url(forAssetPath: "User/JsScript", resolvingSymlinks: true).path.hasPrefix(externalRoot.path))
    }

    @Test("External resource package manifest tracks model, map, and script first-launch sources")
    func externalResourcePackageManifestTracksFirstLaunchSources() {
        let packages = BGIExternalResourcePackage.firstLaunchPackages

        #expect(packages.map(\.id) == [
            "BetterGI.Assets.Model",
            "BetterGI.Assets.Map",
            "bettergi-scripts-list"
        ])
        #expect(BGIExternalResourcePackage.modelAssets.requiredAssetPaths.contains(BGIOnnxModel.bgiFish.assetPath))
        #expect(BGIExternalResourcePackage.modelAssets.requiredAssetPaths.contains(BGIOnnxModel.sileroVad.assetPath))
        #expect(BGIExternalResourcePackage.mapAssets.localDirectory == "Assets/Map")
        #expect(BGIExternalResourcePackage.scriptRepository.sourceKind == .gitShallowClone)
    }

    @Test("Default first-launch asset download sources match BetterGI NuGet packages")
    func defaultFirstLaunchAssetDownloadSourcesMatchBetterGINuGetPackages() throws {
        let requests = BGIExternalResourceBootstrapRequest.defaultFirstLaunchAssetRequests()

        #expect(requests.map(\.package.id) == [
            "BetterGI.Assets.Model",
            "BetterGI.Assets.Map"
        ])
        #expect(requests[0].sources.first?.urls.first?.absoluteString ==
            "https://api.nuget.org/v3-flatcontainer/bettergi.assets.model/1.0.24/bettergi.assets.model.1.0.24.nupkg")
        #expect(requests[1].sources.first?.urls.first?.absoluteString ==
            "https://api.nuget.org/v3-flatcontainer/bettergi.assets.map/1.0.19/bettergi.assets.map.1.0.19.nupkg")
    }

    @Test("Resource installer copies NuGet contentFiles into runtime store")
    func resourceInstallerCopiesNuGetContentFilesIntoRuntimeStore() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-install-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let expandedPackage = tempRoot.appendingPathComponent("ExpandedPackage", isDirectory: true)
        let contentRoot = expandedPackage
            .appendingPathComponent("contentFiles", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)

        let package = testResourcePackage()
        try writeFixtureAsset(
            Data([0x42, 0x47, 0x49]),
            relativePath: "Assets/Model/Fish/bgi_fish.onnx",
            under: contentRoot
        )
        try writeFixtureAsset(
            Data("{\"city\":701}".utf8),
            relativePath: "Assets/Map/Teyvat/city_info.json",
            under: contentRoot
        )

        let installer = BGIExternalResourceInstaller(store: store)
        #expect(installer.coverage(for: package).isSatisfied == false)

        let result = try installer.installContentFiles(from: expandedPackage, package: package)

        #expect(result.installedAssetPaths == package.requiredAssetPaths)
        #expect(result.coverage.isSatisfied)
        #expect(try Data(contentsOf: store.url(forAssetPath: "Assets/Model/Fish/bgi_fish.onnx")) == Data([0x42, 0x47, 0x49]))
        #expect(try String(contentsOf: store.url(forAssetPath: "Assets/Map/Teyvat/city_info.json"), encoding: .utf8) == "{\"city\":701}")
    }

    @Test("Resource installer follows symlinked Application Support roots")
    func resourceInstallerFollowsSymlinkedApplicationSupportRoots() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-install-root-symlink-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let externalRoot = tempRoot.appendingPathComponent("Volumes/Data/Library/Application Support/betterGI-mac", isDirectory: true)
        let linkedRoot = tempRoot.appendingPathComponent("Home/Library/Application Support/betterGI-mac", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: linkedRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: externalRoot)

        let expandedPackage = tempRoot.appendingPathComponent("ExpandedPackage", isDirectory: true)
        let contentRoot = expandedPackage
            .appendingPathComponent("contentFiles", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)

        try writeFixtureAsset(
            Data([0x11]),
            relativePath: "Assets/Model/Fish/bgi_fish.onnx",
            under: contentRoot
        )
        try writeFixtureAsset(
            Data([0x22]),
            relativePath: "Assets/Map/Teyvat/city_info.json",
            under: contentRoot
        )

        let store = BGIRuntimeResourceStore(rootURL: linkedRoot)
        let installer = BGIExternalResourceInstaller(store: store)
        let result = try installer.installContentFiles(from: expandedPackage, package: testResourcePackage())

        #expect(result.coverage.isSatisfied)
        #expect(try isSymbolicLink(at: linkedRoot))
        #expect(try Data(contentsOf: externalRoot.appendingPathComponent("Assets/Model/Fish/bgi_fish.onnx")) == Data([0x11]))
        #expect(try Data(contentsOf: externalRoot.appendingPathComponent("Assets/Map/Teyvat/city_info.json")) == Data([0x22]))
    }

    @Test("Resource installer follows symlinked asset subdirectories")
    func resourceInstallerFollowsSymlinkedAssetSubdirectories() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-install-subdir-symlink-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        try store.createDirectorySkeleton()

        let externalModelURL = tempRoot.appendingPathComponent("Volumes/Data/BetterGI/Assets/Model", isDirectory: true)
        let modelSymlinkURL = store.assetsURL.appendingPathComponent("Model", isDirectory: true)
        try FileManager.default.createDirectory(at: externalModelURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: modelSymlinkURL)
        try FileManager.default.createSymbolicLink(at: modelSymlinkURL, withDestinationURL: externalModelURL)

        let expandedPackage = tempRoot.appendingPathComponent("ExpandedPackage", isDirectory: true)
        let contentRoot = expandedPackage
            .appendingPathComponent("contentFiles", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)

        try writeFixtureAsset(
            Data([0x33]),
            relativePath: "Assets/Model/Fish/bgi_fish.onnx",
            under: contentRoot
        )
        try writeFixtureAsset(
            Data([0x44]),
            relativePath: "Assets/Map/Teyvat/city_info.json",
            under: contentRoot
        )

        let installer = BGIExternalResourceInstaller(store: store)
        let result = try installer.installContentFiles(from: expandedPackage, package: testResourcePackage())

        #expect(result.coverage.isSatisfied)
        #expect(try isSymbolicLink(at: modelSymlinkURL))
        #expect(try Data(contentsOf: externalModelURL.appendingPathComponent("Fish/bgi_fish.onnx")) == Data([0x33]))
        #expect(try Data(contentsOf: store.url(forAssetPath: "Assets/Map/Teyvat/city_info.json")) == Data([0x44]))
    }

    @Test("Resource installer reports missing required package assets before partial install")
    func resourceInstallerReportsMissingRequiredPackageAssetsBeforePartialInstall() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-missing-install-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let expandedPackage = tempRoot.appendingPathComponent("ExpandedPackage", isDirectory: true)
        let contentRoot = expandedPackage
            .appendingPathComponent("contentFiles", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)

        try writeFixtureAsset(
            Data([0x42]),
            relativePath: "Assets/Model/Fish/bgi_fish.onnx",
            under: contentRoot
        )

        let installer = BGIExternalResourceInstaller(store: store)
        do {
            _ = try installer.installContentFiles(from: expandedPackage, package: testResourcePackage())
            Issue.record("Expected missing required source asset")
        } catch let error as BGIExternalResourceInstallerError {
            #expect(error == .missingRequiredSourceAsset("Assets/Map/Teyvat/city_info.json"))
        }

        #expect(FileManager.default.fileExists(atPath: store.url(forAssetPath: "Assets/Model/Fish/bgi_fish.onnx").path) == false)
    }

    @Test("Resource installer extracts nupkg archive before installing contentFiles")
    func resourceInstallerExtractsNupkgArchiveBeforeInstallingContentFiles() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-nupkg-install-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let expandedPackage = tempRoot.appendingPathComponent("PackageRoot", isDirectory: true)
        let contentRoot = expandedPackage
            .appendingPathComponent("contentFiles", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
        try writeFixtureAsset(
            Data([1, 2, 3]),
            relativePath: "Assets/Model/Fish/bgi_fish.onnx",
            under: contentRoot
        )
        try writeFixtureAsset(
            Data([4, 5, 6]),
            relativePath: "Assets/Map/Teyvat/city_info.json",
            under: contentRoot
        )

        let archiveURL = tempRoot.appendingPathComponent("fixture.nupkg")
        try createZipArchive(fromContentsOf: expandedPackage, archiveURL: archiveURL)

        let installer = BGIExternalResourceInstaller(store: store)
        let result = try installer.installNupkg(from: archiveURL, package: testResourcePackage())

        #expect(result.coverage.isSatisfied)
        #expect(try Data(contentsOf: store.url(forAssetPath: "Assets/Model/Fish/bgi_fish.onnx")) == Data([1, 2, 3]))
    }

    @Test("Resource bootstrapper skips downloads when required assets already exist")
    func resourceBootstrapperSkipsDownloadsWhenRequiredAssetsAlreadyExist() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-bootstrap-skip-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let package = testResourcePackage()
        try writeFixtureAsset(
            Data([1]),
            relativePath: "Assets/Model/Fish/bgi_fish.onnx",
            under: store.rootURL
        )
        try writeFixtureAsset(
            Data([2]),
            relativePath: "Assets/Map/Teyvat/city_info.json",
            under: store.rootURL
        )

        let sourceURL = URL(string: "https://example.invalid/bettergi-assets.nupkg")!
        let fetcher = SequencedArchiveFetcher(successArchiveURL: tempRoot.appendingPathComponent("unused.nupkg"))
        let bootstrapper = BGIExternalResourceBootstrapper(store: store, fetcher: fetcher)

        let result = try await bootstrapper.ensure(
            package: package,
            sources: [testDownloadSource(urls: [sourceURL])]
        )

        #expect(result.status == .alreadySatisfied)
        #expect(result.coverage.isSatisfied)
        #expect(await fetcher.requestedURLs() == [])
    }

    @Test("Resource bootstrapper fetches local archive into cache before installing")
    func resourceBootstrapperFetchesLocalArchiveIntoCacheBeforeInstalling() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-bootstrap-file-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let archiveURL = try createTestResourceArchive(under: tempRoot)
        let package = testResourcePackage()
        let bootstrapper = BGIExternalResourceBootstrapper(
            store: store,
            fetcher: BGIExternalResourceURLFetcher()
        )

        let result = try await bootstrapper.ensure(
            package: package,
            sources: [testDownloadSource(urls: [archiveURL])]
        )

        #expect(result.status == .installed)
        #expect(result.coverage.isSatisfied)
        #expect(result.installedAssetPaths == package.requiredAssetPaths)
        #expect(result.archiveURL?.deletingLastPathComponent() == store.downloadCacheURL)
        #expect(try Data(contentsOf: store.url(forAssetPath: "Assets/Model/Fish/bgi_fish.onnx")) == Data([7, 8, 9]))
    }

    @Test("Resource bootstrapper tries later mirrors after a fetch failure")
    func resourceBootstrapperTriesLaterMirrorsAfterFetchFailure() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettergi-mac-bootstrap-mirror-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let store = BGIRuntimeResourceStore(rootURL: tempRoot.appendingPathComponent("AppSupport", isDirectory: true))
        let archiveURL = try createTestResourceArchive(under: tempRoot)
        let firstURL = URL(string: "https://example.invalid/first.nupkg")!
        let secondURL = URL(string: "https://example.invalid/second.nupkg")!
        let fetcher = SequencedArchiveFetcher(
            failingURL: firstURL,
            successArchiveURL: archiveURL
        )
        let bootstrapper = BGIExternalResourceBootstrapper(store: store, fetcher: fetcher)

        let result = try await bootstrapper.ensure(
            package: testResourcePackage(),
            sources: [testDownloadSource(urls: [firstURL, secondURL])]
        )

        #expect(result.status == .installed)
        #expect(result.coverage.isSatisfied)
        #expect(result.failureMessages.count == 1)
        #expect(await fetcher.requestedURLs() == [firstURL, secondURL])
    }
}

private func testResourcePackage() -> BGIExternalResourcePackage {
    BGIExternalResourcePackage(
        id: "Test.Assets",
        version: "1.0.0",
        sourceKind: .nuGetContentFiles,
        sourceDescription: "Synthetic BetterGI contentFiles fixture",
        localDirectory: "Assets",
        requiredAssetPaths: [
            "Assets/Model/Fish/bgi_fish.onnx",
            "Assets/Map/Teyvat/city_info.json"
        ]
    )
}

private func writeFixtureAsset(_ data: Data, relativePath: String, under root: URL) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try data.write(to: url)
}

private func createZipArchive(fromContentsOf sourceDirectory: URL, archiveURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", sourceDirectory.path, archiveURL.path]
    try process.run()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
}

private func testDownloadSource(urls: [URL]) -> BGIExternalResourceDownloadSource {
    BGIExternalResourceDownloadSource(
        id: "test-source",
        packageID: "Test.Assets",
        urls: urls,
        suggestedFileName: "test-assets.nupkg"
    )
}

private func createTestResourceArchive(under tempRoot: URL) throws -> URL {
    let expandedPackage = tempRoot.appendingPathComponent("BootstrapPackageRoot", isDirectory: true)
    let contentRoot = expandedPackage
        .appendingPathComponent("contentFiles", isDirectory: true)
        .appendingPathComponent("any", isDirectory: true)
        .appendingPathComponent("any", isDirectory: true)
    try writeFixtureAsset(
        Data([7, 8, 9]),
        relativePath: "Assets/Model/Fish/bgi_fish.onnx",
        under: contentRoot
    )
    try writeFixtureAsset(
        Data([10, 11, 12]),
        relativePath: "Assets/Map/Teyvat/city_info.json",
        under: contentRoot
    )

    let archiveURL = tempRoot.appendingPathComponent("bootstrap-fixture.nupkg")
    try createZipArchive(fromContentsOf: expandedPackage, archiveURL: archiveURL)
    return archiveURL
}

private func isSymbolicLink(at url: URL) throws -> Bool {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return attributes[.type] as? FileAttributeType == .typeSymbolicLink
}

private enum TestFetchError: Error, Sendable {
    case unavailable
}

private actor SequencedArchiveFetcher: BGIExternalResourceFetching {
    private let failingURL: URL?
    private let successArchiveURL: URL
    private var requests: [URL] = []

    init(failingURL: URL? = nil, successArchiveURL: URL) {
        self.failingURL = failingURL
        self.successArchiveURL = successArchiveURL
    }

    func fetchArchive(
        from url: URL,
        suggestedFileName: String,
        cacheDirectory: URL
    ) async throws -> URL {
        requests.append(url)
        if url == failingURL {
            throw TestFetchError.unavailable
        }
        return successArchiveURL
    }

    func requestedURLs() -> [URL] {
        requests
    }
}
