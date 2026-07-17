import Foundation

struct BGIUserScriptTextEntry: Equatable, Sendable {
    let name: String
    let relativePath: String
    let url: URL
}

struct BGIUserJSONConfigEntry: Equatable, Sendable {
    let name: String
    let relativePath: String
    let url: URL
}

struct BGIUserPathingTreeNode: Equatable, Sendable {
    let fileName: String
    let isDirectory: Bool
    let relativePath: String
    let url: URL
    let iconURL: URL?
    var children: [BGIUserPathingTreeNode]
}

struct BGIUserScriptCatalogSnapshot: Equatable, Sendable {
    let jsProjects: [BGIJSScriptProject]
    let jsIssues: [BGIScriptRepositoryCatalogIssue]
    let pathingRoot: BGIUserPathingTreeNode
    let combatStrategies: [BGIUserScriptTextEntry]
    let geniusInvokationStrategies: [BGIUserScriptTextEntry]
    let keyMouseScripts: [BGIUserJSONConfigEntry]
    let scriptGroups: [BGIUserJSONConfigEntry]
    let loadedScriptGroups: [BGIScriptGroup]
    let scriptGroupIssues: [BGIScriptRepositoryCatalogIssue]
    let oneDragonConfigs: [BGIUserJSONConfigEntry]
}

final class BGIUserScriptCatalogLoader {
    private let store: BGIRuntimeResourceStore
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(
        store: BGIRuntimeResourceStore = .defaultStore(),
        fileManager: FileManager = .default,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.store = store
        self.fileManager = fileManager
        self.decoder = decoder
    }

    func loadSnapshot(createDirectories: Bool = true) throws -> BGIUserScriptCatalogSnapshot {
        if createDirectories {
            try store.createDirectorySkeleton(fileManager: fileManager)
        }

        let jsResult = try loadInstalledJSScriptProjects()
        let scriptGroupResult = try loadScriptGroups()
        return BGIUserScriptCatalogSnapshot(
            jsProjects: jsResult.projects,
            jsIssues: jsResult.issues,
            pathingRoot: try loadPathingTree(),
            combatStrategies: try loadTextEntries(
                under: userDirectory("AutoFight"),
                extension: "txt"
            ),
            geniusInvokationStrategies: try loadTextEntries(
                under: userDirectory("AutoGeniusInvokation"),
                extension: "txt"
            ),
            keyMouseScripts: try loadJSONConfigEntries(
                under: userDirectory("KeyMouseScript"),
                nameKey: nil
            ),
            scriptGroups: try loadJSONConfigEntries(
                under: userDirectory("ScriptGroup"),
                nameKey: "name"
            ),
            loadedScriptGroups: scriptGroupResult.groups,
            scriptGroupIssues: scriptGroupResult.issues,
            oneDragonConfigs: try loadJSONConfigEntries(
                under: userDirectory("OneDragon"),
                nameKey: "Name"
            )
        )
    }

    func loadScriptGroups() throws -> (groups: [BGIScriptGroup], issues: [BGIScriptRepositoryCatalogIssue]) {
        let rootURL = userDirectory("ScriptGroup")
        guard isDirectory(rootURL) else { return ([], []) }

        var groups: [BGIScriptGroup] = []
        var issues: [BGIScriptRepositoryCatalogIssue] = []
        for fileURL in try directoryContents(at: rootURL, properties: [.isRegularFileKey])
            where !isDirectory(fileURL) && fileURL.pathExtension.caseInsensitiveCompare("json") == .orderedSame {
            do {
                groups.append(try decoder.decode(BGIScriptGroup.self, from: Data(contentsOf: fileURL)))
            } catch {
                issues.append(BGIScriptRepositoryCatalogIssue(
                    path: "User/ScriptGroup/\(fileURL.lastPathComponent)",
                    message: error.localizedDescription
                ))
            }
        }
        return (groups, issues)
    }

    func loadInstalledJSScriptProjects() throws -> BGILoadedJSScriptProjects {
        let jsRootURL = userDirectory("JsScript")
        guard isDirectory(jsRootURL) else {
            return BGILoadedJSScriptProjects(projects: [], issues: [])
        }

        let projectURLs = try directoryContents(
            at: jsRootURL,
            properties: [.isDirectoryKey]
        )
        .filter { isDirectory($0) }

        let loader = BGIInstalledJSScriptProjectLoader(
            store: store,
            fileManager: fileManager,
            decoder: decoder
        )
        var projects: [BGIJSScriptProject] = []
        var issues: [BGIScriptRepositoryCatalogIssue] = []
        for projectURL in projectURLs {
            let relativePath = relativePath(from: jsRootURL, to: projectURL)
            do {
                projects.append(try loader.loadProject(
                    at: projectURL,
                    folderName: relativePath
                ))
            } catch {
                issues.append(BGIScriptRepositoryCatalogIssue(
                    path: "User/JsScript/\(relativePath)",
                    message: error.localizedDescription
                ))
            }
        }

        return BGILoadedJSScriptProjects(projects: projects, issues: issues)
    }

    func loadPathingTree() throws -> BGIUserPathingTreeNode {
        let rootURL = userDirectory("AutoPathing")
        if !isDirectory(rootURL) {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
        return try pathingNode(at: rootURL, rootURL: rootURL, isRoot: true)
    }

    private func pathingNode(
        at url: URL,
        rootURL: URL,
        isRoot: Bool = false
    ) throws -> BGIUserPathingTreeNode {
        let children: [BGIUserPathingTreeNode]
        if isDirectory(url) {
            let contents = try directoryContents(
                at: url,
                properties: [.isDirectoryKey, .isRegularFileKey]
            )
            let directories = contents.filter { isDirectory($0) }
            let jsonFiles = contents.filter { fileURL in
                !isDirectory(fileURL)
                    && fileURL.pathExtension.caseInsensitiveCompare("json") == .orderedSame
            }
            children = try directories.map {
                try pathingNode(at: $0, rootURL: rootURL)
            } + jsonFiles.map {
                try pathingNode(at: $0, rootURL: rootURL)
            }
        } else {
            children = []
        }

        let relative = isRoot ? "" : relativePath(from: rootURL, to: url)
        let fileName = isDirectory(url)
            ? url.lastPathComponent
            : url.deletingPathExtension().lastPathComponent
        return BGIUserPathingTreeNode(
            fileName: fileName,
            isDirectory: isDirectory(url),
            relativePath: relative,
            url: url,
            iconURL: iconURL(forPathingNodeAt: url),
            children: children
        )
    }

    private func loadTextEntries(
        under rootURL: URL,
        extension pathExtension: String
    ) throws -> [BGIUserScriptTextEntry] {
        guard isDirectory(rootURL) else { return [] }
        return try recursiveFiles(under: rootURL)
            .filter { $0.pathExtension.caseInsensitiveCompare(pathExtension) == .orderedSame }
            .map { fileURL in
                let fileRelativePath = relativePath(from: rootURL, to: fileURL)
                let relative = fileRelativePath.hasSuffix(".\(pathExtension)")
                    ? String(fileRelativePath.dropLast(pathExtension.count + 1))
                    : fileRelativePath
                return BGIUserScriptTextEntry(
                    name: relative,
                    relativePath: fileRelativePath,
                    url: fileURL
                )
            }
    }

    private func loadJSONConfigEntries(
        under rootURL: URL,
        nameKey: String?
    ) throws -> [BGIUserJSONConfigEntry] {
        guard isDirectory(rootURL) else { return [] }
        return try directoryContents(at: rootURL, properties: [.isRegularFileKey])
            .filter { fileURL in
                !isDirectory(fileURL)
                    && fileURL.pathExtension.caseInsensitiveCompare("json") == .orderedSame
            }
            .map { fileURL in
                let fallbackName = fileURL.deletingPathExtension().lastPathComponent
                let name = try nameKey.flatMap {
                    try jsonStringValue(forKey: $0, in: fileURL)
                } ?? fallbackName
                return BGIUserJSONConfigEntry(
                    name: name.isEmpty ? fallbackName : name,
                    relativePath: relativePath(from: rootURL, to: fileURL),
                    url: fileURL
                )
            }
    }

    private func jsonStringValue(forKey key: String, in url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [String: Any])?[key] as? String
    }

    private func recursiveFiles(under rootURL: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator where !isDirectory(url) {
            urls.append(url)
        }
        return urls.sorted(by: localizedPathOrder)
    }

    private func directoryContents(
        at url: URL,
        properties: Set<URLResourceKey>
    ) throws -> [URL] {
        guard isDirectory(url) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(properties),
            options: [.skipsHiddenFiles]
        )
        .sorted(by: localizedPathOrder)
    }

    private func userDirectory(_ name: String) -> URL {
        store.userURL.appendingPathComponent(name, isDirectory: true)
    }

    private func iconURL(forPathingNodeAt url: URL) -> URL? {
        guard isDirectory(url) else { return url }
        let iconURL = url.appendingPathComponent("icon.ico")
        return fileManager.fileExists(atPath: iconURL.path) ? iconURL : url
    }

    private func relativePath(from rootURL: URL, to url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path != rootPath else { return "" }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func localizedPathOrder(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsName = lhs.lastPathComponent
        let rhsName = rhs.lastPathComponent
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        return lhs.path < rhs.path
    }
}
