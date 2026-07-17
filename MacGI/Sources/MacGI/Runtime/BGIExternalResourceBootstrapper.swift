import Foundation

struct BGIExternalResourceDownloadSource: Identifiable, Equatable, Sendable {
    let id: String
    let packageID: String
    let urls: [URL]
    let suggestedFileName: String

    // MARK: - Multi-source download mirrors

    /// Produce multiple download sources for a NuGet package so the first-launch
    /// bootstrapper can try them in order (fastest mirror wins).
    static func sources(
        for package: BGIExternalResourcePackage,
        nuGetVersion: String? = nil,
        includeNuGetV2: Bool = true,
        includeCnbMirror: Bool = true,
        includeGitHubMirror: Bool = true
    ) -> [BGIExternalResourceDownloadSource] {
        let version = nuGetVersion ?? package.version
        guard let version else { return [] }

        let packageID = package.id.lowercased()
        let fileName = "\(packageID).\(version).nupkg"

        var sources: [BGIExternalResourceDownloadSource] = []

        // Source 1 — NuGet.org flat-container (primary, CDN-backed)
        if let flatContainer = Self.makeSource(
            id: "nuget-flat-container",
            packageID: package.id,
            fileName: fileName,
            urls: [
                "https://api.nuget.org/v3-flatcontainer/\(packageID)/\(version)/\(fileName)"
            ]
        ) {
            sources.append(flatContainer)
        }

        // Source 2 — NuGet.org v2 API (alternative CDN endpoint)
        if includeNuGetV2, let nuGetV2 = Self.makeSource(
            id: "nuget-v2",
            packageID: package.id,
            fileName: fileName,
            urls: [
                "https://www.nuget.org/api/v2/package/\(package.id)/\(version)"
            ]
        ) {
            sources.append(nuGetV2)
        }

        // Source 3 — CNB.cool 镜像 (BetterGI 官方国内镜像)
        // 上游 bettergi-libraries 尚未在 CNB 发布 release，此 URL 为预期路径。
        // 当上游提供 CNB 镜像后取消注释即可启用。
        if includeCnbMirror, let cnbSource = Self.makeSource(
            id: "cnb-mirror",
            packageID: package.id,
            fileName: fileName,
            urls: [
                "https://cnb.cool/bettergi/bettergi-libraries/-/releases/download/v\(version)/\(fileName)"
            ]
        ) {
            // CNB mirror not yet available — keep the source registered so it
            // will be tried when the upstream publishes there.
            sources.append(cnbSource)
        }

        // Source 4 — GitHub Releases 镜像 (由 BetterGI-mac 维护)
        // 当上游 bettergi-libraries 未发布 GitHub release 时，
        // BetterGI-mac 可以将 nupkg 文件上传到自己的 GitHub release 作为镜像。
        if includeGitHubMirror, let ghSource = Self.makeSource(
            id: "github-mirror",
            packageID: package.id,
            fileName: fileName,
            urls: [
                "https://github.com/Jac0b-Shi/BetterGI-mac/releases/download/assets-v\(version)/\(fileName)"
            ]
        ) {
            sources.append(ghSource)
        }

        return sources
    }

    static func defaultSources(for package: BGIExternalResourcePackage) -> [BGIExternalResourceDownloadSource] {
        sources(for: package)
    }

    private static func makeSource(
        id: String,
        packageID: String,
        fileName: String,
        urls: [String]
    ) -> BGIExternalResourceDownloadSource? {
        let resolvedURLs = urls.compactMap(URL.init(string:))
        guard !resolvedURLs.isEmpty else { return nil }
        return BGIExternalResourceDownloadSource(
            id: id,
            packageID: packageID,
            urls: resolvedURLs,
            suggestedFileName: fileName
        )
    }
}

struct BGIExternalResourceBootstrapRequest: Equatable, Sendable {
    let package: BGIExternalResourcePackage
    let sources: [BGIExternalResourceDownloadSource]

    static func defaultFirstLaunchAssetRequests(includeMap: Bool = true) -> [BGIExternalResourceBootstrapRequest] {
        var packages: [BGIExternalResourcePackage] = [.modelAssets]
        if includeMap {
            packages.append(.mapAssets)
        }
        return packages.map { package in
            BGIExternalResourceBootstrapRequest(
                package: package,
                sources: BGIExternalResourceDownloadSource.defaultSources(for: package)
            )
        }
    }
}

protocol BGIExternalResourceFetching: Sendable {
    func fetchArchive(
        from url: URL,
        suggestedFileName: String,
        cacheDirectory: URL
    ) async throws -> URL
}

enum BGIExternalResourceFetchError: LocalizedError, Equatable, Sendable {
    case missingLocalArchive(URL)
    case unsupportedURLScheme(String?)
    case invalidHTTPStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case let .missingLocalArchive(url):
            "BetterGI resource archive does not exist: \(url.path)"
        case let .unsupportedURLScheme(scheme):
            "Unsupported BetterGI resource download URL scheme: \(scheme ?? "<nil>")"
        case let .invalidHTTPStatus(statusCode, url):
            "BetterGI resource download failed with HTTP \(statusCode): \(url)"
        }
    }
}

final class BGIExternalResourceURLFetcher: BGIExternalResourceFetching, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func fetchArchive(
        from url: URL,
        suggestedFileName: String,
        cacheDirectory: URL
    ) async throws -> URL {
        let destinationURL = cacheDirectory
            .appendingPathComponent(Self.sanitizedFileName(suggestedFileName, fallback: url.lastPathComponent))
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        switch url.scheme?.lowercased() {
        case "file":
            guard fileManager.fileExists(atPath: url.path) else {
                throw BGIExternalResourceFetchError.missingLocalArchive(url)
            }
            return try copyReplacingItem(from: url, to: destinationURL)
        case "http", "https":
            let (temporaryURL, response) = try await URLSession.shared.download(from: url)
            if let httpResponse = response as? HTTPURLResponse,
               !(200..<300).contains(httpResponse.statusCode) {
                throw BGIExternalResourceFetchError.invalidHTTPStatus(httpResponse.statusCode, url.absoluteString)
            }
            return try moveReplacingItem(from: temporaryURL, to: destinationURL)
        default:
            throw BGIExternalResourceFetchError.unsupportedURLScheme(url.scheme)
        }
    }

    private func copyReplacingItem(from sourceURL: URL, to destinationURL: URL) throws -> URL {
        if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            return destinationURL
        }
        try removeDestinationIfNeeded(destinationURL)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func moveReplacingItem(from sourceURL: URL, to destinationURL: URL) throws -> URL {
        if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
            return destinationURL
        }
        try removeDestinationIfNeeded(destinationURL)
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    private func removeDestinationIfNeeded(_ destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
    }

    private static func sanitizedFileName(_ suggestedFileName: String, fallback: String) -> String {
        let rawName = suggestedFileName.isEmpty ? fallback : suggestedFileName
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        var sanitized = ""
        for scalar in rawName.unicodeScalars {
            if allowed.contains(scalar) {
                sanitized.unicodeScalars.append(scalar)
            } else {
                sanitized.append("_")
            }
        }
        return sanitized.isEmpty ? "bettergi-resource.nupkg" : sanitized
    }
}

enum BGIExternalResourceBootstrapStatus: String, Equatable, Sendable {
    case alreadySatisfied
    case installed
    case unavailable
}

struct BGIExternalResourceBootstrapResult: Equatable, Sendable {
    let package: BGIExternalResourcePackage
    let status: BGIExternalResourceBootstrapStatus
    let coverage: BGIExternalResourceCoverage
    let installedAssetPaths: [String]
    let archiveURL: URL?
    let failureMessages: [String]
}

enum BGIExternalResourceBootstrapperError: LocalizedError, Equatable, Sendable {
    case allDownloadSourcesFailed(packageID: String, failures: [String])

    var errorDescription: String? {
        switch self {
        case let .allDownloadSourcesFailed(packageID, failures):
            "All BetterGI download sources failed for \(packageID): \(failures.joined(separator: " | "))"
        }
    }
}

final class BGIExternalResourceBootstrapper {
    private let store: BGIRuntimeResourceStore
    private let installer: BGIExternalResourceInstaller
    private let fetcher: any BGIExternalResourceFetching

    init(
        store: BGIRuntimeResourceStore = .defaultStore(),
        installer: BGIExternalResourceInstaller? = nil,
        fetcher: any BGIExternalResourceFetching = BGIExternalResourceURLFetcher()
    ) {
        self.store = store
        self.installer = installer ?? BGIExternalResourceInstaller(store: store)
        self.fetcher = fetcher
    }

    func ensureFirstLaunchAssetPackages(includeMap: Bool = true) async throws -> [BGIExternalResourceBootstrapResult] {
        try await ensure(BGIExternalResourceBootstrapRequest.defaultFirstLaunchAssetRequests(includeMap: includeMap))
    }

    func ensure(_ requests: [BGIExternalResourceBootstrapRequest]) async throws -> [BGIExternalResourceBootstrapResult] {
        var results: [BGIExternalResourceBootstrapResult] = []
        for request in requests {
            results.append(try await ensure(package: request.package, sources: request.sources))
        }
        return results
    }

    func ensure(
        package: BGIExternalResourcePackage,
        sources: [BGIExternalResourceDownloadSource]
    ) async throws -> BGIExternalResourceBootstrapResult {
        try store.createDirectorySkeleton()

        let initialCoverage = installer.coverage(for: package)
        guard !initialCoverage.isSatisfied else {
            return BGIExternalResourceBootstrapResult(
                package: package,
                status: .alreadySatisfied,
                coverage: initialCoverage,
                installedAssetPaths: [],
                archiveURL: nil,
                failureMessages: []
            )
        }

        let attempts = sources.flatMap { source in
            source.urls.map { url in
                (source: source, url: url)
            }
        }
        guard !attempts.isEmpty else {
            return BGIExternalResourceBootstrapResult(
                package: package,
                status: .unavailable,
                coverage: initialCoverage,
                installedAssetPaths: [],
                archiveURL: nil,
                failureMessages: ["No download source configured for \(package.id)"]
            )
        }

        var failures: [String] = []
        for attempt in attempts {
            do {
                let archiveURL = try await fetcher.fetchArchive(
                    from: attempt.url,
                    suggestedFileName: attempt.source.suggestedFileName,
                    cacheDirectory: store.downloadCacheURL
                )
                let installResult = try installer.installNupkg(from: archiveURL, package: package)
                return BGIExternalResourceBootstrapResult(
                    package: package,
                    status: .installed,
                    coverage: installResult.coverage,
                    installedAssetPaths: installResult.installedAssetPaths,
                    archiveURL: archiveURL,
                    failureMessages: failures
                )
            } catch {
                failures.append("\(attempt.source.id) \(attempt.url.absoluteString): \(error.localizedDescription)")
            }
        }

        throw BGIExternalResourceBootstrapperError.allDownloadSourcesFailed(
            packageID: package.id,
            failures: failures
        )
    }
}
