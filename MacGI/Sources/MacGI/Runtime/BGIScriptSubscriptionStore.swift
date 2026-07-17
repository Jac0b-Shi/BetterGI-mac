import Foundation

struct BGIScriptImportRequest: Equatable, Sendable {
    let paths: [String]

    static func decode(fromBetterGIURL string: String) throws -> BGIScriptImportRequest {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let importValue = importQueryValue(from: trimmed) else {
            throw BGIScriptSubscriptionError.missingImportParameter
        }

        let base64 = importValue.replacingOccurrences(of: " ", with: "+")
        guard let data = Data(base64Encoded: base64),
              let decodedString = String(data: data, encoding: .utf8) else {
            throw BGIScriptSubscriptionError.invalidBase64(importValue)
        }

        return try decode(pathJSON: decodedString.removingPercentEncoding ?? decodedString)
    }

    static func decode(pathJSON: String) throws -> BGIScriptImportRequest {
        guard let data = pathJSON.data(using: .utf8) else {
            throw BGIScriptSubscriptionError.invalidPathJSON(pathJSON)
        }

        do {
            let paths = try JSONDecoder().decode([String].self, from: data)
            return BGIScriptImportRequest(paths: try BGIScriptSubscriptionStore.normalizedPaths(paths))
        } catch let error as BGIScriptSubscriptionError {
            throw error
        } catch {
            throw BGIScriptSubscriptionError.invalidPathJSON(pathJSON)
        }
    }

    private static func importQueryValue(from string: String) -> String? {
        if let components = URLComponents(string: string),
           components.scheme?.lowercased() == "bettergi",
           components.host?.lowercased() == "script",
           let value = components.queryItems?.first(where: { $0.name.lowercased() == "import" })?.value,
           !value.isEmpty {
            return value
        }

        guard string.lowercased().hasPrefix("bettergi://script?"),
              let range = string.range(of: "import=", options: [.caseInsensitive]) else {
            return nil
        }

        let queryTail = string[range.upperBound...]
        let value = queryTail.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
        return value?.removingPercentEncoding
    }
}

struct BGIScriptSubscriptionIssue: Equatable, Sendable {
    let path: String
    let message: String
}

struct BGIScriptSubscriptionUpdateResult: Equatable, Sendable {
    let subscribedPaths: [String]
    let expandedCheckoutPaths: [String]
    let checkoutResults: [BGIScriptRepositoryCheckoutResult]
    let cleanedPaths: [String]
    let issues: [BGIScriptSubscriptionIssue]
    let repositoryUpdateResult: BGIScriptRepositoryUpdateResult?
}

enum BGIScriptSubscriptionError: LocalizedError, Equatable, Sendable {
    case missingImportParameter
    case invalidBase64(String)
    case invalidPathJSON(String)
    case unsafePath(String)
    case unsupportedRoot(String)

    var errorDescription: String? {
        switch self {
        case .missingImportParameter:
            "BetterGI script import URL is missing import parameter."
        case let .invalidBase64(value):
            "BetterGI script import payload is not valid base64: \(value)"
        case let .invalidPathJSON(json):
            "BetterGI script import payload is not a JSON string array: \(json)"
        case let .unsafePath(path):
            "Unsafe BetterGI script subscription path: \(path)"
        case let .unsupportedRoot(root):
            "Unsupported BetterGI script subscription root: \(root)"
        }
    }
}

final class BGIScriptSubscriptionStore {
    static let defaultRepositoryFolderName = "bettergi-scripts-list"
    static let supportedRepositoryRoots = Set(BGIScriptRepositoryPathMapping.upstreamDefaults.map(\.repositoryRoot))

    private let store: BGIRuntimeResourceStore
    private let fileManager: FileManager
    private let lock = NSLock()
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    init(store: BGIRuntimeResourceStore = .defaultStore(), fileManager: FileManager = .default) {
        self.store = store
        self.fileManager = fileManager
    }

    var subscriptionsURL: URL {
        store.userURL.appendingPathComponent("Subscriptions", isDirectory: true)
    }

    func subscriptionFileURL(
        repoFolderName: String = BGIScriptSubscriptionStore.defaultRepositoryFolderName
    ) -> URL {
        subscriptionsURL.appendingPathComponent("\(repoFolderName).json")
    }

    func read(repoFolderName: String = BGIScriptSubscriptionStore.defaultRepositoryFolderName) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return readUnlocked(repoFolderName: repoFolderName)
    }

    func write(
        paths: [String],
        repoFolderName: String = BGIScriptSubscriptionStore.defaultRepositoryFolderName
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        try writeUnlocked(paths: try Self.normalizedPaths(paths), repoFolderName: repoFolderName)
    }

    @discardableResult
    func add(
        paths: [String],
        repoFolderName: String = BGIScriptSubscriptionStore.defaultRepositoryFolderName
    ) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let merged = try Self.normalizedPaths(readUnlocked(repoFolderName: repoFolderName) + paths)
        try writeUnlocked(paths: merged, repoFolderName: repoFolderName)
        return merged
    }

    @discardableResult
    func importPaths(
        _ paths: [String],
        using updater: BGIScriptRepositoryUpdater,
        repositoryIndex: BGIScriptRepositoryIndex? = nil,
        repoFolderName: String = BGIScriptSubscriptionStore.defaultRepositoryFolderName
    ) throws -> BGIScriptSubscriptionUpdateResult {
        let normalized = try Self.normalizedPaths(paths)
        let subscribed = try add(paths: normalized, repoFolderName: repoFolderName)
        let index = try repositoryIndex ?? updater.loadRepositoryIndex()
        let expanded = try expandedCheckoutPaths(for: normalized, repositoryIndex: index)
        let existing = try filterExistingRepositoryPaths(expanded, repositoryIndex: index)
        let issues = missingRepositoryPathIssues(expandedCheckoutPaths: expanded, existingPaths: existing)
        let checkoutResults = try updater.checkout(paths: existing)
        let cleaned = try cleanSubscribedPaths(
            subscribed + existing,
            repositoryIndex: index,
            repoFolderName: repoFolderName
        )

        return BGIScriptSubscriptionUpdateResult(
            subscribedPaths: subscribed,
            expandedCheckoutPaths: expanded,
            checkoutResults: checkoutResults,
            cleanedPaths: cleaned,
            issues: issues,
            repositoryUpdateResult: nil
        )
    }

    @discardableResult
    func updateSubscribedScripts(
        using updater: BGIScriptRepositoryUpdater,
        channels: [BGIScriptRepositoryChannel] = BGIScriptRepositoryChannel.upstreamDefaults,
        updateRepository: Bool = true,
        repoFolderName: String = BGIScriptSubscriptionStore.defaultRepositoryFolderName
    ) async throws -> BGIScriptSubscriptionUpdateResult {
        let subscribed = read(repoFolderName: repoFolderName)
        guard !subscribed.isEmpty else {
            return BGIScriptSubscriptionUpdateResult(
                subscribedPaths: [],
                expandedCheckoutPaths: [],
                checkoutResults: [],
                cleanedPaths: [],
                issues: [],
                repositoryUpdateResult: nil
            )
        }

        let repositoryUpdateResult = updateRepository
            ? try await updater.ensureCenterRepository(channels: channels)
            : nil
        let index = try updater.loadRepositoryIndex()
        let expanded = try expandedCheckoutPaths(for: subscribed, repositoryIndex: index)
        let existing = try filterExistingRepositoryPaths(expanded, repositoryIndex: index)
        let issues = missingRepositoryPathIssues(expandedCheckoutPaths: expanded, existingPaths: existing)
        let checkoutResults = try updater.checkout(paths: existing)
        let cleaned = try cleanSubscribedPaths(
            subscribed + existing,
            repositoryIndex: index,
            repoFolderName: repoFolderName
        )

        return BGIScriptSubscriptionUpdateResult(
            subscribedPaths: subscribed,
            expandedCheckoutPaths: expanded,
            checkoutResults: checkoutResults,
            cleanedPaths: cleaned,
            issues: issues,
            repositoryUpdateResult: repositoryUpdateResult
        )
    }

    func expandedCheckoutPaths(
        for paths: [String],
        repositoryIndex: BGIScriptRepositoryIndex
    ) throws -> [String] {
        let normalized = try Self.normalizedPaths(paths, preservingInputOrder: true)
        var result: [String] = []

        for path in normalized {
            let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 1,
                  let rootNode = repositoryIndex.indexes.first(where: { $0.name == path && $0.type == .directory }) else {
                result.append(path)
                continue
            }

            result.append(contentsOf: rootNode.children
                .filter { $0.type == .directory }
                .map { "\(path)/\($0.name)" })
        }

        return Self.removingDuplicatesPreservingOrder(result)
    }

    func filterExistingRepositoryPaths(
        _ paths: [String],
        repositoryIndex: BGIScriptRepositoryIndex
    ) throws -> [String] {
        let availablePaths = Set(repositoryIndex.flattenedEntries(includeDirectories: true).map(\.path))
        return try Self.normalizedPaths(paths, preservingInputOrder: true)
            .filter { availablePaths.contains($0) }
    }

    @discardableResult
    func cleanSubscribedPaths(
        _ paths: [String]? = nil,
        repositoryIndex: BGIScriptRepositoryIndex,
        repoFolderName: String = BGIScriptSubscriptionStore.defaultRepositoryFolderName
    ) throws -> [String] {
        let inputPaths = paths ?? read(repoFolderName: repoFolderName)
        let expandedInputPaths = try expandedCheckoutPaths(for: inputPaths, repositoryIndex: repositoryIndex)
        let allPaths = try Self.normalizedPaths(inputPaths + expandedInputPaths)
        var pathsToKeep = Set<String>()

        for path in allPaths where path.contains("/") {
            let root = String(path.split(separator: "/", omittingEmptySubsequences: true).first ?? "")
            guard Self.supportedRepositoryRoots.contains(root) else { continue }
            guard fileManager.fileExists(atPath: try destinationURL(forRepositoryPath: path).path) else { continue }
            guard !pathsToKeep.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
            pathsToKeep.insert(path)
        }

        let parentChildMap = directParentChildMap(for: repositoryIndex)
        var hasNewPaths = true
        while hasNewPaths {
            hasNewPaths = false
            for (parentPath, directChildren) in parentChildMap {
                guard !pathsToKeep.contains(parentPath),
                      directChildren.allSatisfy({ pathsToKeep.contains($0) }) else {
                    continue
                }
                pathsToKeep.insert(parentPath)
                hasNewPaths = true
            }
        }

        let cleaned = Self.removingPathsCoveredByParents(Array(pathsToKeep))
        try write(paths: cleaned, repoFolderName: repoFolderName)
        return cleaned
    }

    static func normalizedPaths(
        _ paths: [String],
        preservingInputOrder: Bool = false
    ) throws -> [String] {
        let normalized = try paths.map(normalizeRepositoryPath)
        return preservingInputOrder
            ? removingDuplicatesPreservingOrder(normalized)
            : Array(Set(normalized)).sorted()
    }

    static func normalizeRepositoryPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !parts.isEmpty,
              !trimmed.hasPrefix("/"),
              !parts.contains("."),
              !parts.contains("..") else {
            throw BGIScriptSubscriptionError.unsafePath(path)
        }

        let root = parts[0].lowercased()
        guard supportedRepositoryRoots.contains(root) else {
            throw BGIScriptSubscriptionError.unsupportedRoot(parts[0])
        }

        return ([root] + parts.dropFirst()).joined(separator: "/")
    }

    private func readUnlocked(repoFolderName: String) -> [String] {
        let fileURL = subscriptionFileURL(repoFolderName: repoFolderName)
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              !data.isEmpty,
              let decoded = try? decoder.decode([String].self, from: data) else {
            return []
        }

        return (try? Self.normalizedPaths(decoded)) ?? decoded.compactMap { try? Self.normalizeRepositoryPath($0) }.sorted()
    }

    private func writeUnlocked(paths: [String], repoFolderName: String) throws {
        let fileURL = subscriptionFileURL(repoFolderName: repoFolderName)
        try fileManager.createDirectory(at: subscriptionsURL, withIntermediateDirectories: true)

        guard !paths.isEmpty else {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            return
        }

        let data = try encoder.encode(paths)
        try data.write(to: fileURL, options: .atomic)
    }

    private func destinationURL(forRepositoryPath path: String) throws -> URL {
        let normalizedPath = try Self.normalizeRepositoryPath(path)
        let parts = normalizedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let mapping = BGIScriptRepositoryPathMapping.upstreamDefaults.first(where: { $0.repositoryRoot == parts[0] }) else {
            throw BGIScriptSubscriptionError.unsupportedRoot(parts[0])
        }

        let remainingPath = parts.dropFirst().joined(separator: "/")
        let destinationRoot = store.userURL.appendingPathComponent(mapping.userDirectoryName, isDirectory: true)
        return remainingPath.isEmpty
            ? destinationRoot
            : destinationRoot.appendingPathComponent(remainingPath)
    }

    private func directParentChildMap(for repositoryIndex: BGIScriptRepositoryIndex) -> [String: [String]] {
        var result: [String: Set<String>] = [:]
        for entry in repositoryIndex.flattenedEntries(includeDirectories: true) {
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.count > 1 else { continue }
            let parentPath = parts.dropLast().joined(separator: "/")
            result[parentPath, default: []].insert(entry.path)
        }

        return result.mapValues { Array($0).sorted() }
    }

    private func missingRepositoryPathIssues(
        expandedCheckoutPaths: [String],
        existingPaths: [String]
    ) -> [BGIScriptSubscriptionIssue] {
        let existing = Set(existingPaths)
        return expandedCheckoutPaths
            .filter { !existing.contains($0) }
            .map {
                BGIScriptSubscriptionIssue(
                    path: $0,
                    message: "Repository path no longer exists in bettergi-scripts-list."
                )
            }
    }

    private static func removingDuplicatesPreservingOrder(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }

    private static func removingPathsCoveredByParents(_ paths: [String]) -> [String] {
        var result: [String] = []
        for path in paths.sorted() {
            guard !result.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
                continue
            }
            result.append(path)
        }
        return result
    }
}
