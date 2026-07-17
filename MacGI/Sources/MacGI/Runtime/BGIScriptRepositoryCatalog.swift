import Foundation

enum BGIJSONValue: Equatable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([BGIJSONValue])
    case object([String: BGIJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([BGIJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: BGIJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

struct BGIScriptAuthor: Equatable, Sendable, Decodable {
    let name: String
    let link: String?

    enum CodingKeys: String, CodingKey {
        case name
        case link
        case links
    }

    init(name: String, link: String?) {
        self.name = name
        self.link = link
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        link = try container.decodeIfPresent(String.self, forKey: .link)
            ?? container.decodeIfPresent(String.self, forKey: .links)
    }
}

struct BGIScriptRepositoryIndex: Equatable, Sendable, Decodable {
    let time: String?
    let url: String?
    let file: String?
    let indexes: [BGIScriptRepositoryIndexNode]

    enum CodingKeys: String, CodingKey {
        case time
        case url
        case file
        case indexes
    }

    init(time: String?, url: String?, file: String?, indexes: [BGIScriptRepositoryIndexNode]) {
        self.time = time
        self.url = url
        self.file = file
        self.indexes = indexes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        time = try container.decodeIfPresent(String.self, forKey: .time)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        file = try container.decodeIfPresent(String.self, forKey: .file)
        indexes = try container.decodeIfPresent([BGIScriptRepositoryIndexNode].self, forKey: .indexes) ?? []
    }

    func flattenedEntries(includeDirectories: Bool = true) -> [BGIScriptRepositoryCatalogEntry] {
        indexes.flatMap { node in
            node.flattenedEntries(parentPath: "", includeDirectories: includeDirectories)
        }
    }
}

struct BGIScriptRepositoryIndexNode: Equatable, Sendable, Decodable {
    enum NodeType: String, Equatable, Sendable, Decodable {
        case directory
        case file
    }

    let name: String
    let type: NodeType
    let version: String?
    let author: String?
    let authors: [BGIScriptAuthor]
    let description: String?
    let tags: [String]
    let lastUpdated: String?
    let hasUpdate: Bool
    let children: [BGIScriptRepositoryIndexNode]

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case version
        case author
        case authors
        case description
        case tags
        case lastUpdated
        case hasUpdate
        case children
    }

    init(
        name: String,
        type: NodeType,
        version: String? = nil,
        author: String? = nil,
        authors: [BGIScriptAuthor] = [],
        description: String? = nil,
        tags: [String] = [],
        lastUpdated: String? = nil,
        hasUpdate: Bool = false,
        children: [BGIScriptRepositoryIndexNode] = []
    ) {
        self.name = name
        self.type = type
        self.version = version
        self.author = author
        self.authors = authors
        self.description = description
        self.tags = tags
        self.lastUpdated = lastUpdated
        self.hasUpdate = hasUpdate
        self.children = children
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        type = try container.decodeIfPresent(NodeType.self, forKey: .type) ?? .file
        version = try container.decodeIfPresent(String.self, forKey: .version)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        authors = try container.decodeIfPresent([BGIScriptAuthor].self, forKey: .authors) ?? []
        description = try container.decodeIfPresent(String.self, forKey: .description)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        lastUpdated = try container.decodeIfPresent(String.self, forKey: .lastUpdated)
        hasUpdate = try container.decodeIfPresent(Bool.self, forKey: .hasUpdate) ?? false
        children = try container.decodeIfPresent([BGIScriptRepositoryIndexNode].self, forKey: .children) ?? []
    }

    func flattenedEntries(parentPath: String, includeDirectories: Bool) -> [BGIScriptRepositoryCatalogEntry] {
        let path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
        var entries: [BGIScriptRepositoryCatalogEntry] = []
        if includeDirectories || type == .file {
            entries.append(BGIScriptRepositoryCatalogEntry(node: self, path: path))
        }
        entries.append(contentsOf: children.flatMap {
            $0.flattenedEntries(parentPath: path, includeDirectories: includeDirectories)
        })
        return entries
    }
}

struct BGIScriptRepositoryCatalogEntry: Equatable, Sendable {
    enum Root: String, Equatable, Sendable {
        case js
        case pathing
        case combat
        case tcg
        case other
    }

    let path: String
    let root: Root
    let name: String
    let type: BGIScriptRepositoryIndexNode.NodeType
    let version: String?
    let author: String?
    let authors: [BGIScriptAuthor]
    let description: String?
    let tags: [String]
    let lastUpdated: String?
    let hasUpdate: Bool

    init(node: BGIScriptRepositoryIndexNode, path: String) {
        self.path = path
        root = Root(rawValue: path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? "") ?? .other
        name = node.name
        type = node.type
        version = node.version
        author = node.author
        authors = node.authors
        description = node.description
        tags = node.tags
        lastUpdated = node.lastUpdated
        hasUpdate = node.hasUpdate
    }
}

struct BGIJSScriptManifest: Equatable, Sendable, Decodable {
    let manifestVersion: Int
    let name: String
    let version: String
    let bgiVersion: String?
    let description: String
    let authors: [BGIScriptAuthor]
    let main: String
    let settingsUI: String?
    let scripts: [String]
    let library: [String]
    let savedFiles: [String]
    let httpAllowedUrls: [String]
    let dependencies: [String]
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case manifestVersion = "manifest_version"
        case name
        case version
        case bgiVersion = "bgi_version"
        case description
        case authors
        case main
        case settingsUI = "settings_ui"
        case scripts
        case library
        case savedFiles = "saved_files"
        case httpAllowedUrls = "http_allowed_urls"
        case dependencies
        case tags
    }

    init(
        manifestVersion: Int = 1,
        name: String,
        version: String,
        bgiVersion: String? = nil,
        description: String = "",
        authors: [BGIScriptAuthor] = [],
        main: String,
        settingsUI: String? = nil,
        scripts: [String] = [],
        library: [String] = [],
        savedFiles: [String] = [],
        httpAllowedUrls: [String] = [],
        dependencies: [String] = [],
        tags: [String] = []
    ) {
        self.manifestVersion = manifestVersion
        self.name = name
        self.version = version
        self.bgiVersion = bgiVersion
        self.description = description
        self.authors = authors
        self.main = main
        self.settingsUI = settingsUI
        self.scripts = scripts
        self.library = library
        self.savedFiles = savedFiles
        self.httpAllowedUrls = httpAllowedUrls
        self.dependencies = dependencies
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decodeIfPresent(Int.self, forKey: .manifestVersion) ?? 1
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? ""
        bgiVersion = try container.decodeIfPresent(String.self, forKey: .bgiVersion)
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        authors = try container.decodeIfPresent([BGIScriptAuthor].self, forKey: .authors) ?? []
        main = try container.decodeIfPresent(String.self, forKey: .main) ?? ""
        settingsUI = try container.decodeIfPresent(String.self, forKey: .settingsUI)
        scripts = try container.decodeIfPresent([String].self, forKey: .scripts) ?? []
        library = try container.decodeIfPresent([String].self, forKey: .library) ?? []
        savedFiles = try container.decodeIfPresent([String].self, forKey: .savedFiles) ?? []
        httpAllowedUrls = try container.decodeIfPresent([String].self, forKey: .httpAllowedUrls) ?? []
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

struct BGIJSScriptSettingItem: Equatable, Sendable, Decodable {
    let name: String?
    let type: String
    let label: String?
    let options: [String]?
    let cascadeOptions: [String: [String]]?
    let defaultValue: BGIJSONValue?

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case label
        case options
        case cascadeOptions = "cascade_options"
        case defaultValue = "default"
    }

    init(
        name: String?,
        type: String,
        label: String?,
        options: [String]? = nil,
        cascadeOptions: [String: [String]]? = nil,
        defaultValue: BGIJSONValue? = nil
    ) {
        self.name = name
        self.type = type
        self.label = label
        self.options = options
        self.cascadeOptions = cascadeOptions
        self.defaultValue = defaultValue
    }
}

struct BGIJSScriptProject: Equatable, Sendable {
    let folderName: String
    let repositoryPath: String
    let projectURL: URL
    let manifest: BGIJSScriptManifest
    let settings: [BGIJSScriptSettingItem]
    let mainScriptURL: URL

    var requiresSettingsUI: Bool {
        !(manifest.settingsUI ?? "").isEmpty
    }
}

struct BGILoadedJSScriptProjects: Equatable, Sendable {
    let projects: [BGIJSScriptProject]
    let issues: [BGIScriptRepositoryCatalogIssue]
}

struct BGIScriptRepositoryCatalogIssue: Equatable, Sendable {
    let path: String
    let message: String
}

final class BGIScriptRepositoryCatalogLoader {
    private let fileManager: FileManager
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, decoder: JSONDecoder = JSONDecoder()) {
        self.fileManager = fileManager
        self.decoder = decoder
    }

    func loadIndex(from repositoryURL: URL) throws -> BGIScriptRepositoryIndex {
        let indexURL = repositoryURL.appendingPathComponent("repo.json")
        let data = try Data(contentsOf: indexURL)
        return try decoder.decode(BGIScriptRepositoryIndex.self, from: data)
    }

    func loadJSScriptProjects(from repositoryContentURL: URL) throws -> BGILoadedJSScriptProjects {
        let jsRootURL = repositoryContentURL.appendingPathComponent("js", isDirectory: true)
        guard fileManager.fileExists(atPath: jsRootURL.path) else {
            return BGILoadedJSScriptProjects(projects: [], issues: [
                BGIScriptRepositoryCatalogIssue(path: "js", message: "JS repository root is missing")
            ])
        }

        let projectURLs = try fileManager.contentsOfDirectory(
            at: jsRootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        var projects: [BGIJSScriptProject] = []
        var issues: [BGIScriptRepositoryCatalogIssue] = []
        for projectURL in projectURLs {
            do {
                projects.append(try loadJSScriptProject(projectURL))
            } catch {
                issues.append(BGIScriptRepositoryCatalogIssue(
                    path: "js/\(projectURL.lastPathComponent)",
                    message: error.localizedDescription
                ))
            }
        }

        return BGILoadedJSScriptProjects(projects: projects, issues: issues)
    }

    private func loadJSScriptProject(_ projectURL: URL) throws -> BGIJSScriptProject {
        let manifestURL = projectURL.appendingPathComponent("manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(BGIJSScriptManifest.self, from: manifestData)

        let mainScriptURL = projectURL.appendingPathComponent(manifest.main)
        guard !manifest.name.isEmpty else {
            throw BGIScriptRepositoryCatalogLoaderError.invalidManifest("manifest.json: name is required.")
        }
        guard !manifest.version.isEmpty else {
            throw BGIScriptRepositoryCatalogLoaderError.invalidManifest("manifest.json: version is required.")
        }
        guard !manifest.main.isEmpty else {
            throw BGIScriptRepositoryCatalogLoaderError.invalidManifest("manifest.json: main script is required.")
        }
        guard fileManager.fileExists(atPath: mainScriptURL.path) else {
            throw BGIScriptRepositoryCatalogLoaderError.missingMainScript(manifest.main)
        }

        let settings = try loadSettings(projectURL: projectURL, manifest: manifest)
        return BGIJSScriptProject(
            folderName: projectURL.lastPathComponent,
            repositoryPath: "js/\(projectURL.lastPathComponent)",
            projectURL: projectURL,
            manifest: manifest,
            settings: settings,
            mainScriptURL: mainScriptURL
        )
    }

    private func loadSettings(projectURL: URL, manifest: BGIJSScriptManifest) throws -> [BGIJSScriptSettingItem] {
        guard let settingsUI = manifest.settingsUI, !settingsUI.isEmpty else {
            return []
        }

        let settingsURL = projectURL.appendingPathComponent(settingsUI)
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            throw BGIScriptRepositoryCatalogLoaderError.missingSettingsFile(settingsUI)
        }

        let settingsData = try Data(contentsOf: settingsURL)
        return try decoder.decode([BGIJSScriptSettingItem].self, from: settingsData)
    }
}

enum BGIScriptRepositoryCatalogLoaderError: LocalizedError, Equatable, Sendable {
    case invalidManifest(String)
    case missingMainScript(String)
    case missingSettingsFile(String)

    var errorDescription: String? {
        switch self {
        case let .invalidManifest(message):
            message
        case let .missingMainScript(path):
            "main js file not found: \(path)"
        case let .missingSettingsFile(path):
            "settings ui file not found: \(path)"
        }
    }
}
