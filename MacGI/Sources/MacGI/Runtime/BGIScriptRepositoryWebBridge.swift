import Foundation

enum BGIScriptRepositoryWebBridgeError: LocalizedError, Equatable, Sendable {
    case missingRepository
    case missingRepositoryIndex
    case unsafeRepositoryPath(String)
    case invalidRepositoryIndex

    var errorDescription: String? {
        switch self {
        case .missingRepository:
            "BetterGI script repository folder does not exist."
        case .missingRepositoryIndex:
            "BetterGI script repository index file does not exist."
        case .unsafeRepositoryPath(let path):
            "Unsafe BetterGI script repository web path: \(path)"
        case .invalidRepositoryIndex:
            "BetterGI script repository index JSON is invalid."
        }
    }
}

final class BGIScriptRepositoryWebBridge {
    static let notFoundPayload = "404"

    private static let allowedTextExtensions: Set<String> = [
        "txt", "md", "json", "js", "ts",
        "vue", "css", "html", "csv", "xml",
        "yaml", "yml", "ini", "config"
    ]

    private static let allowedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "ico"
    ]

    private let updater: BGIScriptRepositoryUpdater
    private let subscriptionStore: BGIScriptSubscriptionStore
    private let fileManager: FileManager

    init(
        updater: BGIScriptRepositoryUpdater = BGIScriptRepositoryUpdater(),
        subscriptionStore: BGIScriptSubscriptionStore = BGIScriptSubscriptionStore(),
        fileManager: FileManager = .default
    ) {
        self.updater = updater
        self.subscriptionStore = subscriptionStore
        self.fileManager = fileManager
    }

    func repoJSON() throws -> String {
        try requireRepository()
        return try String(contentsOf: repoJSONURLForBridge(), encoding: .utf8)
    }

    func subscribedScriptPathsJSON() -> String {
        let paths = subscriptionStore.read()
        guard let data = try? JSONEncoder().encode(paths),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    @discardableResult
    func importURI(_ uri: String) throws -> BGIScriptSubscriptionUpdateResult {
        let request = try BGIScriptImportRequest.decode(fromBetterGIURL: uri)
        return try subscriptionStore.importPaths(request.paths, using: updater)
    }

    func filePayload(forRepositoryPath path: String) -> String {
        do {
            let fileURL = try repositoryFileURL(for: path)
            guard fileManager.fileExists(atPath: fileURL.path), !isSymlink(fileURL) else {
                return Self.notFoundPayload
            }

            let fileExtension = fileURL.pathExtension.lowercased()
            if Self.allowedTextExtensions.contains(fileExtension) {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                return content.isEmpty ? Self.notFoundPayload : content
            }

            if Self.allowedImageExtensions.contains(fileExtension) {
                let data = try Data(contentsOf: fileURL)
                return data.isEmpty ? Self.notFoundPayload : data.base64EncodedString()
            }

            return Self.notFoundPayload
        } catch {
            return Self.notFoundPayload
        }
    }

    func mimeType(forExtension fileExtension: String) -> String {
        switch fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() {
        case "png":
            "image/png"
        case "jpg", "jpeg":
            "image/jpeg"
        case "gif":
            "image/gif"
        case "bmp":
            "image/bmp"
        case "webp":
            "image/webp"
        case "svg":
            "image/svg+xml"
        case "ico":
            "image/x-icon"
        default:
            "application/octet-stream"
        }
    }

    @discardableResult
    func resetUpdateFlag(forRepositoryPath path: String) throws -> Bool {
        try requireRepository()
        let normalizedPath = try normalizeWebRepositoryPath(path)
        let pathParts = normalizedPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !pathParts.isEmpty else {
            throw BGIScriptRepositoryWebBridgeError.unsafeRepositoryPath(path)
        }

        let indexURL = try repoJSONURLForBridge()
        let data = try Data(contentsOf: indexURL)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let indexes = root["indexes"] as? [[String: Any]] else {
            throw BGIScriptRepositoryWebBridgeError.invalidRepositoryIndex
        }

        let result = resetUpdateFlag(in: indexes, pathParts: pathParts, currentIndex: 0)
        guard result.didReset else { return false }

        root["indexes"] = result.nodes
        let output = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try output.write(to: indexURL, options: .atomic)
        return true
    }

    @discardableResult
    func clearUpdateMarkers() throws -> Bool {
        try requireRepository()
        let repoJSONURL = updater.centerRepositoryURL.appendingPathComponent("repo.json")
        guard fileManager.fileExists(atPath: repoJSONURL.path) else {
            throw BGIScriptRepositoryWebBridgeError.missingRepositoryIndex
        }

        if fileManager.fileExists(atPath: updater.repoUpdatedJSONURL.path) {
            try fileManager.removeItem(at: updater.repoUpdatedJSONURL)
        }
        try fileManager.copyItem(at: repoJSONURL, to: updater.repoUpdatedJSONURL)
        return true
    }

    private func requireRepository() throws {
        guard fileManager.fileExists(atPath: updater.centerRepositoryURL.path) else {
            throw BGIScriptRepositoryWebBridgeError.missingRepository
        }
    }

    private func repoJSONURLForBridge() throws -> URL {
        if fileManager.fileExists(atPath: updater.repoUpdatedJSONURL.path) {
            return updater.repoUpdatedJSONURL
        }

        let repoJSONURL = updater.centerRepositoryURL.appendingPathComponent("repo.json")
        guard fileManager.fileExists(atPath: repoJSONURL.path) else {
            throw BGIScriptRepositoryWebBridgeError.missingRepositoryIndex
        }
        return repoJSONURL
    }

    private func repositoryFileURL(for path: String) throws -> URL {
        let normalizedPath = try normalizeWebRepositoryPath(path.removingPercentEncoding ?? path)
        let baseURL = updater.repositoryContentURL.standardizedFileURL
        let fileURL = baseURL.appendingPathComponent(normalizedPath).standardizedFileURL

        guard fileURL.path == baseURL.path || fileURL.path.hasPrefix(baseURL.path + "/") else {
            throw BGIScriptRepositoryWebBridgeError.unsafeRepositoryPath(path)
        }
        return fileURL
    }

    private func normalizeWebRepositoryPath(_ path: String) throws -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !parts.isEmpty,
              !trimmed.hasPrefix("/"),
              !parts.contains("."),
              !parts.contains("..") else {
            throw BGIScriptRepositoryWebBridgeError.unsafeRepositoryPath(path)
        }

        return parts.joined(separator: "/")
    }

    private func resetUpdateFlag(
        in nodes: [[String: Any]],
        pathParts: [String],
        currentIndex: Int
    ) -> (nodes: [[String: Any]], didReset: Bool) {
        var updatedNodes: [[String: Any]] = []
        var didReset = false

        for var node in nodes {
            if node["name"] as? String == pathParts[currentIndex] {
                if currentIndex == pathParts.count - 1 {
                    resetUpdateFlagInSubtree(&node)
                    didReset = true
                } else if let children = node["children"] as? [[String: Any]] {
                    let result = resetUpdateFlag(
                        in: children,
                        pathParts: pathParts,
                        currentIndex: currentIndex + 1
                    )
                    node["children"] = result.nodes
                    didReset = result.didReset
                }
            }
            updatedNodes.append(node)
        }

        return (updatedNodes, didReset)
    }

    private func resetUpdateFlagInSubtree(_ node: inout [String: Any]) {
        if let hasUpdate = node["hasUpdate"] as? Bool, hasUpdate {
            node["hasUpdate"] = false
        }

        guard let children = node["children"] as? [[String: Any]] else { return }
        node["children"] = children.map { child in
            var child = child
            resetUpdateFlagInSubtree(&child)
            return child
        }
    }

    private func isSymlink(_ url: URL) -> Bool {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }
}
