import Foundation

struct BGIScriptRepositoryChannel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let url: URL

    static let cnb = BGIScriptRepositoryChannel(
        id: "CNB",
        name: "CNB",
        url: URL(string: "https://cnb.cool/bettergi/bettergi-scripts-list")!
    )

    static let gitCode = BGIScriptRepositoryChannel(
        id: "GitCode",
        name: "GitCode",
        url: URL(string: "https://gitcode.com/huiyadanli/bettergi-scripts-list")!
    )

    static let gitHub = BGIScriptRepositoryChannel(
        id: "GitHub",
        name: "GitHub",
        url: URL(string: "https://github.com/babalae/bettergi-scripts-list")!
    )

    static let upstreamDefaults: [BGIScriptRepositoryChannel] = [.cnb, .gitCode, .gitHub]
}

struct BGIScriptRepositoryPathMapping: Equatable, Sendable {
    let repositoryRoot: String
    let userDirectoryName: String

    static let upstreamDefaults: [BGIScriptRepositoryPathMapping] = [
        BGIScriptRepositoryPathMapping(repositoryRoot: "pathing", userDirectoryName: "AutoPathing"),
        BGIScriptRepositoryPathMapping(repositoryRoot: "js", userDirectoryName: "JsScript"),
        BGIScriptRepositoryPathMapping(repositoryRoot: "combat", userDirectoryName: "AutoFight"),
        BGIScriptRepositoryPathMapping(repositoryRoot: "tcg", userDirectoryName: "AutoGeniusInvokation")
    ]
}

enum BGIScriptRepositoryUpdateStatus: String, Equatable, Sendable {
    case cloned
    case updated
    case alreadyUpToDate
}

struct BGIScriptRepositoryUpdateResult: Equatable, Sendable {
    let repositoryURL: URL
    let channel: BGIScriptRepositoryChannel
    let status: BGIScriptRepositoryUpdateStatus
    let failureMessages: [String]
}

struct BGIScriptRepositoryCheckoutResult: Equatable, Sendable {
    let sourcePath: String
    let destinationURL: URL
}

enum BGIScriptRepositoryUpdaterError: LocalizedError, Equatable, Sendable {
    case gitUnavailable(String)
    case noChannelsConfigured
    case allChannelsFailed([String])
    case invalidRepository(URL, missingPath: String)
    case unsupportedRepositoryRoot(String)
    case unsafeRepositoryPath(String)
    case missingSourcePath(String)
    case gitCommandFailed(arguments: [String], exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .gitUnavailable(path):
            "Git executable is unavailable: \(path)"
        case .noChannelsConfigured:
            "No BetterGI script repository channels are configured."
        case let .allChannelsFailed(failures):
            "All BetterGI script repository channels failed: \(failures.joined(separator: " | "))"
        case let .invalidRepository(url, missingPath):
            "BetterGI script repository at \(url.path) is missing \(missingPath)"
        case let .unsupportedRepositoryRoot(root):
            "Unsupported BetterGI script repository root: \(root)"
        case let .unsafeRepositoryPath(path):
            "Unsafe BetterGI script repository path: \(path)"
        case let .missingSourcePath(path):
            "BetterGI script repository path does not exist: \(path)"
        case let .gitCommandFailed(arguments, exitCode, stderr):
            "Git command failed (\(arguments.joined(separator: " "))), exit \(exitCode): \(stderr)"
        }
    }
}

final class BGIScriptRepositoryUpdater {
    private let store: BGIRuntimeResourceStore
    private let fileManager: FileManager
    private let gitURL: URL
    private let repositoryFolderName = "bettergi-scripts-list"
    private let releaseBranchName = "release"

    init(
        store: BGIRuntimeResourceStore = .defaultStore(),
        fileManager: FileManager = .default,
        gitURL: URL = URL(fileURLWithPath: "/usr/bin/git")
    ) {
        self.store = store
        self.fileManager = fileManager
        self.gitURL = gitURL
    }

    var centerRepositoryURL: URL {
        store.reposURL.appendingPathComponent(repositoryFolderName, isDirectory: true)
    }

    var repositoryContentURL: URL {
        centerRepositoryURL.appendingPathComponent("repo", isDirectory: true)
    }

    var repoUpdatedJSONURL: URL {
        centerRepositoryURL.appendingPathComponent("repo_updated.json")
    }

    func ensureCenterRepository(
        channels: [BGIScriptRepositoryChannel] = BGIScriptRepositoryChannel.upstreamDefaults
    ) async throws -> BGIScriptRepositoryUpdateResult {
        try store.createDirectorySkeleton(fileManager: fileManager)
        guard fileManager.isExecutableFile(atPath: gitURL.path) else {
            throw BGIScriptRepositoryUpdaterError.gitUnavailable(gitURL.path)
        }
        guard !channels.isEmpty else {
            throw BGIScriptRepositoryUpdaterError.noChannelsConfigured
        }

        var failures: [String] = []
        let previousRepositoryIndexContent = readRepositoryUpdateBaseline()
        for channel in channels {
            do {
                let status = try updateCenterRepository(from: channel)
                try validateCenterRepository()
                _ = try generateRepositoryUpdateMarkers(previousContent: previousRepositoryIndexContent)
                return BGIScriptRepositoryUpdateResult(
                    repositoryURL: centerRepositoryURL,
                    channel: channel,
                    status: status,
                    failureMessages: failures
                )
            } catch {
                failures.append("\(channel.name) \(channel.url.absoluteString): \(error.localizedDescription)")
            }
        }

        throw BGIScriptRepositoryUpdaterError.allChannelsFailed(failures)
    }

    func checkout(paths: [String]) throws -> [BGIScriptRepositoryCheckoutResult] {
        try store.createDirectorySkeleton(fileManager: fileManager)
        try validateCenterRepository()

        var results: [BGIScriptRepositoryCheckoutResult] = []
        for path in paths {
            let normalizedPath = try normalizeRepositoryPath(path)
            let sourceURL = repositoryContentURL.appendingPathComponent(normalizedPath)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw BGIScriptRepositoryUpdaterError.missingSourcePath(normalizedPath)
            }

            let destinationURL = try destinationURL(forRepositoryPath: normalizedPath)
            let savedFilesBackupURL = try backupJSScriptSavedFilesIfNeeded(
                repositoryPath: normalizedPath,
                destinationURL: destinationURL
            )
            try copyReplacingItem(from: sourceURL, to: destinationURL)
            try restoreJSScriptSavedFilesIfNeeded(
                backupURL: savedFilesBackupURL,
                destinationURL: destinationURL
            )
            try resolveJSScriptPackageDependenciesIfNeeded(
                repositoryPath: normalizedPath,
                destinationURL: destinationURL
            )
            results.append(BGIScriptRepositoryCheckoutResult(
                sourcePath: normalizedPath,
                destinationURL: destinationURL
            ))
        }
        return results
    }

    func destinationURL(forRepositoryPath path: String) throws -> URL {
        let normalizedPath = try normalizeRepositoryPath(path)
        let parts = normalizedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let root = parts.first else {
            throw BGIScriptRepositoryUpdaterError.unsafeRepositoryPath(path)
        }
        guard let mapping = Self.pathMappingByRoot[root] else {
            throw BGIScriptRepositoryUpdaterError.unsupportedRepositoryRoot(root)
        }

        let remainingPath = parts.dropFirst().joined(separator: "/")
        let destinationRoot = store.userURL.appendingPathComponent(mapping.userDirectoryName, isDirectory: true)
        return remainingPath.isEmpty
            ? destinationRoot
            : destinationRoot.appendingPathComponent(remainingPath)
    }

    func readRepositoryFile(_ relativePath: String) throws -> String? {
        let normalizedPath = try normalizeRepositoryPath(relativePath)
        let url = repositoryContentURL.appendingPathComponent(normalizedPath)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func loadRepositoryIndex() throws -> BGIScriptRepositoryIndex {
        try BGIScriptRepositoryCatalogLoader(fileManager: fileManager)
            .loadIndex(from: centerRepositoryURL)
    }

    func loadJSScriptProjects() throws -> BGILoadedJSScriptProjects {
        try BGIScriptRepositoryCatalogLoader(fileManager: fileManager)
            .loadJSScriptProjects(from: repositoryContentURL)
    }

    @discardableResult
    func generateRepositoryUpdateMarkers(previousContent: String? = nil) throws -> BGIScriptRepositoryUpdateMarkerResult {
        let repoJSONURL = centerRepositoryURL.appendingPathComponent("repo.json")
        let newContent = try String(contentsOf: repoJSONURL, encoding: .utf8)
        let markerResult = BGIScriptRepositoryUpdateMarkerGenerator()
            .generate(previousJSON: previousContent ?? readRepositoryUpdateBaseline(), newJSON: newContent)
        try markerResult.content.write(to: repoUpdatedJSONURL, atomically: true, encoding: .utf8)
        return markerResult
    }

    private static let pathMappingByRoot = Dictionary(
        uniqueKeysWithValues: BGIScriptRepositoryPathMapping.upstreamDefaults.map {
            ($0.repositoryRoot, $0)
        }
    )

    private func updateCenterRepository(from channel: BGIScriptRepositoryChannel) throws -> BGIScriptRepositoryUpdateStatus {
        if isValidGitRepository(centerRepositoryURL) {
            return try fetchExistingRepository(from: channel)
        }

        if fileManager.fileExists(atPath: centerRepositoryURL.path) {
            try fileManager.removeItem(at: centerRepositoryURL)
        }
        try cloneRepository(from: channel.url, to: centerRepositoryURL)
        return .cloned
    }

    private func fetchExistingRepository(from channel: BGIScriptRepositoryChannel) throws -> BGIScriptRepositoryUpdateStatus {
        let oldHead = try currentHeadSHA(in: centerRepositoryURL)
        _ = try runGit(["-C", centerRepositoryURL.path, "remote", "set-url", "origin", channel.url.absoluteString])
        _ = try runGit(["-C", centerRepositoryURL.path, "fetch", "--depth", "1", "origin", releaseBranchName])
        _ = try runGit(["-C", centerRepositoryURL.path, "checkout", "-B", releaseBranchName, "FETCH_HEAD"])
        _ = try runGit(["-C", centerRepositoryURL.path, "reset", "--hard", "FETCH_HEAD"])
        _ = try runGit(["-C", centerRepositoryURL.path, "clean", "-fd"])
        let newHead = try currentHeadSHA(in: centerRepositoryURL)
        return oldHead == newHead ? .alreadyUpToDate : .updated
    }

    private func cloneRepository(from url: URL, to destinationURL: URL) throws {
        let temporaryURL = store.reposURL
            .appendingPathComponent(".bettergi-scripts-list-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        _ = try runGit([
            "clone",
            "--depth", "1",
            "--branch", releaseBranchName,
            "--single-branch",
            url.absoluteString,
            temporaryURL.path
        ])

        try replaceDirectoryPreservingSymlink(from: temporaryURL, to: destinationURL)
    }

    private func validateCenterRepository() throws {
        for path in BGIExternalResourcePackage.scriptRepository.requiredAssetPaths {
            let url = store.url(forAssetPath: path)
            guard fileManager.fileExists(atPath: url.path) else {
                throw BGIScriptRepositoryUpdaterError.invalidRepository(centerRepositoryURL, missingPath: path)
            }
        }
    }

    private func readRepositoryUpdateBaseline() -> String? {
        if fileManager.fileExists(atPath: repoUpdatedJSONURL.path),
           let content = try? String(contentsOf: repoUpdatedJSONURL, encoding: .utf8) {
            return content
        }

        let repoJSONURL = centerRepositoryURL.appendingPathComponent("repo.json")
        if fileManager.fileExists(atPath: repoJSONURL.path),
           let content = try? String(contentsOf: repoJSONURL, encoding: .utf8) {
            return content
        }

        return nil
    }

    private func isValidGitRepository(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.appendingPathComponent(".git", isDirectory: true).path) else {
            return false
        }
        return (try? runGit(["-C", url.path, "rev-parse", "--is-inside-work-tree"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)) == "true"
    }

    private func currentHeadSHA(in repositoryURL: URL) throws -> String {
        try runGit(["-C", repositoryURL.path, "rev-parse", "HEAD"]).stdout
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeRepositoryPath(_ path: String) throws -> String {
        let parts = path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !parts.isEmpty,
              !path.hasPrefix("/"),
              !parts.contains(".."),
              !parts.contains(".") else {
            throw BGIScriptRepositoryUpdaterError.unsafeRepositoryPath(path)
        }

        return parts.joined(separator: "/")
    }

    private func backupJSScriptSavedFilesIfNeeded(
        repositoryPath: String,
        destinationURL: URL
    ) throws -> URL? {
        guard isJSScriptRepositoryPath(repositoryPath),
              let manifest = try loadJSScriptManifest(repositoryPath: repositoryPath),
              !manifest.savedFiles.isEmpty,
              fileManager.fileExists(atPath: destinationURL.path) else {
            return nil
        }

        let backupURL = store.userURL
            .appendingPathComponent("Temp", isDirectory: true)
            .appendingPathComponent(repositoryPath, isDirectory: true)
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        var hasBackup = false
        for rawPattern in manifest.savedFiles {
            let pattern = rawPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty, isSafeSavedFilePattern(pattern) else { continue }

            let normalizedPattern = normalizedRelativePath(pattern)
            let trimmedDirectoryPattern = normalizedPattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let targetURL = destinationURL.appendingPathComponent(trimmedDirectoryPattern)

            if pattern.hasSuffix("/") || isDirectory(targetURL) {
                guard isDirectory(targetURL) else { continue }
                let relativePath = trimmedDirectoryPattern
                let backupTargetURL = backupURL.appendingPathComponent(relativePath, isDirectory: true)
                try copyReplacingItem(from: targetURL, to: backupTargetURL)
                hasBackup = true
                continue
            }

            for matchedURL in try matchedSavedFileURLs(baseURL: destinationURL, pattern: normalizedPattern) {
                guard let relativePath = relativePath(of: matchedURL, from: destinationURL) else { continue }
                let backupTargetURL = backupURL.appendingPathComponent(relativePath)
                try fileManager.createDirectory(
                    at: backupTargetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: backupTargetURL.path) {
                    try fileManager.removeItem(at: backupTargetURL)
                }
                try fileManager.copyItem(at: matchedURL, to: backupTargetURL)
                hasBackup = true
            }
        }

        if !hasBackup {
            try? fileManager.removeItem(at: backupURL)
            return nil
        }
        return backupURL
    }

    private func restoreJSScriptSavedFilesIfNeeded(backupURL: URL?, destinationURL: URL) throws {
        guard let backupURL, fileManager.fileExists(atPath: backupURL.path) else { return }
        defer { try? fileManager.removeItem(at: backupURL) }

        for itemURL in try recursiveItemURLs(under: backupURL) {
            guard let relativePath = relativePath(of: itemURL, from: backupURL) else { continue }
            let restoreURL = destinationURL.appendingPathComponent(relativePath)
            if isSymbolicLink(itemURL) {
                try fileManager.createDirectory(
                    at: restoreURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: restoreURL.path) {
                    try fileManager.removeItem(at: restoreURL)
                }
                try fileManager.copyItem(at: itemURL, to: restoreURL)
            } else if isDirectory(itemURL) {
                try fileManager.createDirectory(at: restoreURL, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(
                    at: restoreURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fileManager.fileExists(atPath: restoreURL.path) {
                    try fileManager.removeItem(at: restoreURL)
                }
                try fileManager.copyItem(at: itemURL, to: restoreURL)
            }
        }
    }

    private func resolveJSScriptPackageDependenciesIfNeeded(
        repositoryPath: String,
        destinationURL: URL
    ) throws {
        guard isJSScriptRepositoryPath(repositoryPath) else { return }

        let baseDestinationURL: URL
        var processingQueue: [URL]
        if isDirectory(destinationURL) {
            baseDestinationURL = destinationURL
            processingQueue = try recursiveFileURLs(under: destinationURL)
                .filter { $0.pathExtension.caseInsensitiveCompare("js") == .orderedSame }
        } else if fileManager.fileExists(atPath: destinationURL.path) {
            baseDestinationURL = destinationURL.deletingLastPathComponent()
            processingQueue = [destinationURL]
        } else {
            return
        }

        let packagesURL = baseDestinationURL.appendingPathComponent("packages", isDirectory: true)
        if fileManager.fileExists(atPath: packagesURL.path) {
            try fileManager.removeItem(at: packagesURL)
        }

        let importRegex = try NSRegularExpression(
            pattern: #"(import\s+([\w\d_$]+)\s+from\s+['"]|import\s+(?:[\w\s{},*]*?from\s+)?['"]|export\s+(?:[\w\s{},*]*?from\s+)?['"]|import\s+['"]|require\s*\(\s*['"])([^'"\n]+)(['"])"#,
            options: []
        )
        var processedFiles = Set<String>()

        while !processingQueue.isEmpty {
            let currentFileURL = processingQueue.removeFirst()
            let currentPath = currentFileURL.standardizedFileURL.path
            guard !processedFiles.contains(currentPath) else { continue }
            processedFiles.insert(currentPath)
            guard fileManager.fileExists(atPath: currentPath),
                  let content = try? String(contentsOf: currentFileURL, encoding: .utf8) else {
                continue
            }

            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            for match in importRegex.matches(in: content, range: range) {
                guard match.numberOfRanges > 3,
                      let pathRange = Range(match.range(at: 3), in: content) else {
                    continue
                }

                let importedPath = String(content[pathRange])
                guard let packagePath = packageDependencyPath(
                    importedPath: importedPath,
                    currentFileURL: currentFileURL,
                    baseDestinationURL: baseDestinationURL
                ) else {
                    continue
                }

                let destinationPackageURL = baseDestinationURL.appendingPathComponent(packagePath)
                let isCode = packagePath.lowercased().hasSuffix(".js")
                if fileManager.fileExists(atPath: destinationPackageURL.path) {
                    if isCode, !processedFiles.contains(destinationPackageURL.standardizedFileURL.path) {
                        processingQueue.append(destinationPackageURL)
                    }
                    continue
                }

                if try checkoutRepositoryRootPath(
                    packagePath,
                    to: destinationPackageURL,
                    queue: &processingQueue
                ) {
                    continue
                }

                let lastPathComponent = packagePath.split(separator: "/").last.map(String.init) ?? ""
                if isCode || !lastPathComponent.contains(".") {
                    _ = try checkoutRepositoryRootPath(
                        packagePath + ".js",
                        to: URL(fileURLWithPath: destinationPackageURL.path + ".js"),
                        queue: &processingQueue
                    )
                }
            }
        }
    }

    private func loadJSScriptManifest(repositoryPath: String) throws -> BGIJSScriptManifest? {
        guard isJSScriptRepositoryPath(repositoryPath) else { return nil }

        let manifestURL = repositoryContentURL
            .appendingPathComponent(repositoryPath)
            .appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else { return nil }

        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(BGIJSScriptManifest.self, from: data)
    }

    private func isJSScriptRepositoryPath(_ path: String) -> Bool {
        path == "js" || path.hasPrefix("js/")
    }

    private func checkoutRepositoryRootPath(
        _ sourcePath: String,
        to destinationURL: URL,
        queue: inout [URL]
    ) throws -> Bool {
        let normalizedPath = try normalizeRepositoryPath(sourcePath)
        let sourceURL = centerRepositoryURL.appendingPathComponent(normalizedPath)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return false }

        try copyReplacingItem(from: sourceURL, to: destinationURL)
        if destinationURL.pathExtension.caseInsensitiveCompare("js") == .orderedSame {
            queue.append(destinationURL)
        } else if isDirectory(destinationURL) {
            queue.append(contentsOf: try recursiveFileURLs(under: destinationURL).filter {
                $0.pathExtension.caseInsensitiveCompare("js") == .orderedSame
            })
        }
        return true
    }

    private func packageDependencyPath(
        importedPath: String,
        currentFileURL: URL,
        baseDestinationURL: URL
    ) -> String? {
        let normalizedImport = normalizedRelativePath(importedPath)
        if let range = normalizedImport.range(of: "packages/", options: [.caseInsensitive]) {
            return String(normalizedImport[range.lowerBound...])
        }

        guard normalizedImport.hasPrefix("."),
              currentFileURL.standardizedFileURL.path.hasPrefix(
                baseDestinationURL.appendingPathComponent("packages", isDirectory: true).standardizedFileURL.path + "/"
              ) else {
            return nil
        }

        let relativeDirectory = relativePath(
            of: currentFileURL.deletingLastPathComponent(),
            from: baseDestinationURL
        ) ?? ""
        let dependencyURL = baseDestinationURL
            .appendingPathComponent(relativeDirectory, isDirectory: true)
            .appendingPathComponent(normalizedImport)
            .standardizedFileURL
        guard let dependencyPath = relativePath(of: dependencyURL, from: baseDestinationURL),
              dependencyPath.lowercased().hasPrefix("packages/") else {
            return nil
        }
        return dependencyPath
    }

    private func matchedSavedFileURLs(baseURL: URL, pattern: String) throws -> [URL] {
        if isRegexSavedFilePattern(pattern) {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            return try recursiveFileURLs(under: baseURL).filter { fileURL in
                guard let relativePath = relativePath(of: fileURL, from: baseURL) else { return false }
                let range = NSRange(relativePath.startIndex..<relativePath.endIndex, in: relativePath)
                return regex.firstMatch(in: relativePath, range: range) != nil
            }
        }

        let directory = (pattern as NSString).deletingLastPathComponent
        let filePattern = (pattern as NSString).lastPathComponent
        let searchURL = directory.isEmpty ? baseURL : baseURL.appendingPathComponent(directory, isDirectory: true)
        guard isDirectory(searchURL) else { return [] }

        let regex = try NSRegularExpression(
            pattern: wildcardPatternToRegex(filePattern),
            options: [.caseInsensitive]
        )
        return try fileManager.contentsOfDirectory(at: searchURL, includingPropertiesForKeys: nil)
            .filter { !isDirectory($0) }
            .filter { fileURL in
                let name = fileURL.lastPathComponent
                let range = NSRange(name.startIndex..<name.endIndex, in: name)
                return regex.firstMatch(in: name, range: range) != nil
            }
    }

    private func recursiveFileURLs(under rootURL: URL) throws -> [URL] {
        try recursiveItemURLs(under: rootURL).filter { !isDirectory($0) }
    }

    private func recursiveItemURLs(under rootURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            return []
        }

        var result: [URL] = []
        for case let itemURL as URL in enumerator {
            result.append(itemURL)
            if isSymbolicLink(itemURL) {
                enumerator.skipDescendants()
            }
        }
        return result
    }

    private func isSafeSavedFilePattern(_ pattern: String) -> Bool {
        let parts = normalizedRelativePath(pattern)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        return !parts.isEmpty
            && !pattern.hasPrefix("/")
            && !parts.contains(".")
            && !parts.contains("..")
    }

    private func normalizedRelativePath(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
    }

    private func relativePath(of url: URL, from baseURL: URL) -> String? {
        let basePath = baseURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == basePath { return "" }
        guard path.hasPrefix(basePath + "/") else { return nil }
        return String(path.dropFirst(basePath.count + 1))
    }

    private func isRegexSavedFilePattern(_ pattern: String) -> Bool {
        pattern.hasPrefix("^") || pattern.contains(".*") || pattern.contains(#"\d"#) || pattern.contains(#"\w"#)
    }

    private func wildcardPatternToRegex(_ pattern: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: #"\*"#, with: ".*")
            .replacingOccurrences(of: #"\?"#, with: ".")
        return "^\(escaped)$"
    }

    private func copyReplacingItem(from sourceURL: URL, to destinationURL: URL) throws {
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if isDirectory(sourceURL), isDirectorySymlink(destinationURL) {
            try replaceDirectoryContents(from: sourceURL, to: destinationURL)
            return
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func replaceDirectoryPreservingSymlink(from sourceURL: URL, to destinationURL: URL) throws {
        if isDirectorySymlink(destinationURL) {
            try replaceDirectoryContents(from: sourceURL, to: destinationURL)
            return
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func replaceDirectoryContents(from sourceURL: URL, to destinationURL: URL) throws {
        let targetURL = destinationURL.resolvingSymlinksInPath()
        try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true)
        for childURL in try fileManager.contentsOfDirectory(at: targetURL, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: childURL)
        }
        for childURL in try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil) {
            try fileManager.copyItem(
                at: childURL,
                to: targetURL.appendingPathComponent(childURL.lastPathComponent)
            )
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isDirectorySymlink(_ url: URL) -> Bool {
        isDirectory(url) && isSymbolicLink(url)
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private struct GitCommandResult {
        let stdout: String
        let stderr: String
    }

    @discardableResult
    private func runGit(_ arguments: [String]) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = gitURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw BGIScriptRepositoryUpdaterError.gitCommandFailed(
                arguments: arguments,
                exitCode: process.terminationStatus,
                stderr: stderr
            )
        }

        return GitCommandResult(stdout: stdout, stderr: stderr)
    }
}
