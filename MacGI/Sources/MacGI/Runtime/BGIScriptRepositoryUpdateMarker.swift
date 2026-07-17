import Foundation

struct BGIScriptRepositoryUpdateMarkerResult: Equatable, Sendable {
    let content: String
    let overlapRatio: Double?
    let inheritedPreviousMarkers: Bool
}

enum BGIScriptRepositoryUpdateMarkerError: LocalizedError, Equatable, Sendable {
    case invalidRepositoryJSON
    case missingIndexes

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryJSON:
            "BetterGI script repository index JSON is invalid."
        case .missingIndexes:
            "BetterGI script repository index JSON is missing indexes."
        }
    }
}

struct BGIScriptRepositoryUpdateMarkerGenerator: Sendable {
    let overlapThreshold: Double

    init(overlapThreshold: Double = 0.5) {
        self.overlapThreshold = overlapThreshold
    }

    func generate(previousJSON: String?, newJSON: String) -> BGIScriptRepositoryUpdateMarkerResult {
        guard let previousJSON, !previousJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return BGIScriptRepositoryUpdateMarkerResult(
                content: newJSON,
                overlapRatio: nil,
                inheritedPreviousMarkers: false
            )
        }

        let overlapRatio = calculateOverlapRatio(oldJSON: previousJSON, newJSON: newJSON)
        guard overlapRatio >= overlapThreshold else {
            return BGIScriptRepositoryUpdateMarkerResult(
                content: newJSON,
                overlapRatio: overlapRatio,
                inheritedPreviousMarkers: false
            )
        }

        let markedContent = (try? addUpdateMarkers(oldJSON: previousJSON, newJSON: newJSON)) ?? newJSON
        return BGIScriptRepositoryUpdateMarkerResult(
            content: markedContent,
            overlapRatio: overlapRatio,
            inheritedPreviousMarkers: markedContent != newJSON
        )
    }

    func calculateOverlapRatio(oldJSON: String, newJSON: String) -> Double {
        do {
            let oldRoot = try parseJSONObject(oldJSON)
            let newRoot = try parseJSONObject(newJSON)
            let oldPaths = directoryPaths(from: oldRoot)
            let newPaths = directoryPaths(from: newRoot)

            if oldPaths.isEmpty && newPaths.isEmpty { return 1.0 }
            if oldPaths.isEmpty || newPaths.isEmpty { return 0.0 }

            let intersectionCount = oldPaths.intersection(newPaths).count
            let minCount = min(oldPaths.count, newPaths.count)
            return minCount > 0 ? Double(intersectionCount) / Double(minCount) : 0.0
        } catch {
            return -1.0
        }
    }

    private func addUpdateMarkers(oldJSON: String, newJSON: String) throws -> String {
        let oldRoot = try parseJSONObject(oldJSON)
        var newRoot = try parseJSONObject(newJSON)

        guard let oldIndexes = oldRoot["indexes"] as? [[String: Any]],
              let newIndexes = newRoot["indexes"] as? [[String: Any]] else {
            throw BGIScriptRepositoryUpdateMarkerError.missingIndexes
        }

        newRoot["indexes"] = newIndexes.map { node in
            markNodeUpdates(newNode: node, oldNodes: oldIndexes).node
        }

        return try serializeJSONObject(newRoot)
    }

    private func markNodeUpdates(
        newNode: [String: Any],
        oldNodes: [[String: Any]]
    ) -> (node: [String: Any], hasUpdate: Bool) {
        var node = newNode
        guard let newName = node["name"] as? String, !newName.isEmpty else {
            return (node, false)
        }

        let oldNode = oldNodes.first { ($0["name"] as? String) == newName }
        var hasDirectUpdate = false
        var hasChildUpdate = false

        if let oldNode {
            if isTruthy(oldNode["hasUpdate"]) {
                node["hasUpdate"] = true
                hasDirectUpdate = true
            }

            let oldTime = parseLastUpdated(oldNode["lastUpdated"] as? String)
            let newTime = parseLastUpdated(node["lastUpdated"] as? String)
            if newTime > oldTime {
                node["hasUpdate"] = true
                hasDirectUpdate = true
            }
        } else {
            node["hasUpdate"] = true
            hasDirectUpdate = true
        }

        if let newChildren = node["children"] as? [[String: Any]], !newChildren.isEmpty {
            let oldChildren = oldNode?["children"] as? [[String: Any]] ?? []
            let markedChildren = newChildren.map { child in
                markNodeUpdates(newNode: child, oldNodes: oldChildren)
            }

            node["children"] = markedChildren.map(\.node)

            for childResult in markedChildren where childResult.hasUpdate {
                hasChildUpdate = true

                let child = childResult.node
                let children = child["children"] as? [[String: Any]]
                let isLeafChild = children?.isEmpty ?? true
                if isLeafChild && isTruthy(child["hasUpdate"]) {
                    let parentTime = parseLastUpdated(node["lastUpdated"] as? String)
                    let childTime = parseLastUpdated(child["lastUpdated"] as? String)

                    node["hasUpdate"] = true
                    hasDirectUpdate = true

                    if childTime > parentTime, let childLastUpdated = child["lastUpdated"] {
                        node["lastUpdated"] = childLastUpdated
                    }
                }
            }
        }

        return (node, hasDirectUpdate || hasChildUpdate)
    }

    private func directoryPaths(from root: [String: Any]) -> Set<String> {
        guard let indexes = root["indexes"] as? [[String: Any]] else { return [] }

        var paths = Set<String>()
        collectDirectoryPaths(indexes, prefix: "", paths: &paths)
        return paths
    }

    private func collectDirectoryPaths(
        _ nodes: [[String: Any]],
        prefix: String,
        paths: inout Set<String>
    ) {
        for node in nodes {
            guard let name = node["name"] as? String, !name.isEmpty else { continue }
            guard (node["type"] as? String) == "directory" else { continue }

            let fullPath = prefix.isEmpty ? name : "\(prefix)/\(name)"
            paths.insert(fullPath)

            if let children = node["children"] as? [[String: Any]], !children.isEmpty {
                collectDirectoryPaths(children, prefix: fullPath, paths: &paths)
            }
        }
    }

    private func parseJSONObject(_ content: String) throws -> [String: Any] {
        guard let data = content.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BGIScriptRepositoryUpdateMarkerError.invalidRepositoryJSON
        }
        return object
    }

    private func serializeJSONObject(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func isTruthy(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? String { return value.caseInsensitiveCompare("true") == .orderedSame }
        return false
    }

    private func parseLastUpdated(_ value: String?) -> Date {
        guard let value, !value.isEmpty else { return .distantPast }

        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }

        for format in [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyyMMddHHmmss"
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return .distantPast
    }
}
