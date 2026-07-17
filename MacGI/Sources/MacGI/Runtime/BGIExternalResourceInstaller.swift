import Foundation

struct BGIExternalResourceCoverage: Equatable, Sendable {
    let package: BGIExternalResourcePackage
    let resolvedAssetPaths: [String]
    let missingAssetPaths: [String]

    var isSatisfied: Bool { missingAssetPaths.isEmpty }
}

struct BGIExternalResourceInstallResult: Equatable, Sendable {
    let package: BGIExternalResourcePackage
    let installedAssetPaths: [String]
    let coverage: BGIExternalResourceCoverage
}

enum BGIExternalResourceInstallerError: LocalizedError, Equatable {
    case missingContentFilesRoot(URL)
    case missingRequiredSourceAsset(String)
    case unsupportedArchiveExtractor(String)
    case archiveExtractionFailed(path: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .missingContentFilesRoot(url):
            "BetterGI resource package has no contentFiles/any/any root: \(url.path)"
        case let .missingRequiredSourceAsset(path):
            "BetterGI resource package is missing required asset: \(path)"
        case let .unsupportedArchiveExtractor(path):
            "macOS archive extractor is unavailable: \(path)"
        case let .archiveExtractionFailed(path, exitCode, stderr):
            "Failed to extract BetterGI resource package \(path), exit \(exitCode): \(stderr)"
        }
    }
}

final class BGIExternalResourceInstaller {
    private let store: BGIRuntimeResourceStore
    private let fileManager: FileManager

    init(store: BGIRuntimeResourceStore = .defaultStore(), fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    func coverage(for package: BGIExternalResourcePackage) -> BGIExternalResourceCoverage {
        var resolved: [String] = []
        var missing: [String] = []

        for path in package.requiredAssetPaths {
            if fileManager.fileExists(atPath: store.url(forAssetPath: path).path) {
                resolved.append(path)
            } else {
                missing.append(path)
            }
        }

        return BGIExternalResourceCoverage(
            package: package,
            resolvedAssetPaths: resolved,
            missingAssetPaths: missing
        )
    }

    func installContentFiles(
        from expandedPackageURL: URL,
        package: BGIExternalResourcePackage
    ) throws -> BGIExternalResourceInstallResult {
        try store.createDirectorySkeleton(fileManager: fileManager)

        let contentRoot = contentFilesRoot(in: expandedPackageURL)
        guard fileManager.fileExists(atPath: contentRoot.path) else {
            throw BGIExternalResourceInstallerError.missingContentFilesRoot(contentRoot)
        }

        for path in package.requiredAssetPaths {
            let sourceURL = contentRoot.appendingPathComponent(path)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw BGIExternalResourceInstallerError.missingRequiredSourceAsset(path)
            }
        }

        let installed = try package.requiredAssetPaths.map { path in
            let sourceURL = contentRoot.appendingPathComponent(path)
            let destinationURL = store.url(forAssetPath: path)
            try copyReplacingItem(from: sourceURL, to: destinationURL)
            return path
        }

        return BGIExternalResourceInstallResult(
            package: package,
            installedAssetPaths: installed,
            coverage: coverage(for: package)
        )
    }

    func installNupkg(
        from archiveURL: URL,
        package: BGIExternalResourcePackage
    ) throws -> BGIExternalResourceInstallResult {
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("bettergi-resource-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try extractZipArchive(archiveURL, to: temporaryRoot)
        return try installContentFiles(from: temporaryRoot, package: package)
    }

    private func contentFilesRoot(in expandedPackageURL: URL) -> URL {
        expandedPackageURL
            .appendingPathComponent("contentFiles", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
            .appendingPathComponent("any", isDirectory: true)
    }

    private func copyReplacingItem(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func extractZipArchive(_ archiveURL: URL, to destinationURL: URL) throws {
        let dittoURL = URL(fileURLWithPath: "/usr/bin/ditto")
        guard fileManager.isExecutableFile(atPath: dittoURL.path) else {
            throw BGIExternalResourceInstallerError.unsupportedArchiveExtractor(dittoURL.path)
        }

        let process = Process()
        process.executableURL = dittoURL
        process.arguments = ["-x", "-k", archiveURL.path, destinationURL.path]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw BGIExternalResourceInstallerError.archiveExtractionFailed(
                path: archiveURL.path,
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }
    }
}
