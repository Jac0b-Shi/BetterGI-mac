import Foundation

struct BGIRuntimeResourceStore: Equatable, Sendable {
    let rootURL: URL

    var userURL: URL { rootURL.appendingPathComponent("User", isDirectory: true) }
    var reposURL: URL { rootURL.appendingPathComponent("Repos", isDirectory: true) }
    var cacheURL: URL { rootURL.appendingPathComponent("Cache", isDirectory: true) }
    var logURL: URL { rootURL.appendingPathComponent("log", isDirectory: true) }
    var assetsURL: URL { rootURL.appendingPathComponent("Assets", isDirectory: true) }
    var runURL: URL { rootURL.appendingPathComponent("Run", isDirectory: true) }
    var downloadCacheURL: URL { cacheURL.appendingPathComponent("Downloads", isDirectory: true) }
    var modelCacheURL: URL { cacheURL.appendingPathComponent("Model", isDirectory: true) }
    var mapsURL: URL { assetsURL.appendingPathComponent("Map", isDirectory: true) }
    var resolvedRootURL: URL { rootURL.resolvingSymlinksInPath() }

    static func defaultStore(fileManager: FileManager = .default) -> BGIRuntimeResourceStore {
        BGIRuntimeResourceStore(rootURL: defaultRootURL(fileManager: fileManager))
    }

    static func defaultRootURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport.appendingPathComponent("betterGI-mac", isDirectory: true)
    }

    static func defaultSearchRoots(fileManager: FileManager = .default) -> [URL] {
        [defaultRootURL(fileManager: fileManager)]
    }

    func url(forAssetPath path: String, resolvingSymlinks: Bool = false) -> URL {
        let baseURL = resolvingSymlinks ? resolvedRootURL : rootURL
        return baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    func userScriptGroupURL(for name: String) -> URL {
        userURL.appendingPathComponent("ScriptGroup/\(name).json")
    }

    func createDirectorySkeleton(fileManager: FileManager = .default) throws {
        for directory in requiredDirectories {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        for relativePath in Self.coreBootstrapTemplatePaths {
            let destination = assetsURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: destination.path) { continue }
            guard let source = BGIAssetResolver.url(for: relativePath) else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: relativePath])
            }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private static let coreBootstrapTemplatePaths = [
        "GameTask/Common/Element/Assets/1920x1080/paimon_menu.png",
        "GameTask/Common/Element/Assets/1920x1080/primogem.png",
        "GameTask/AutoFight/Assets/1920x1080/confirm.png",
        "GameTask/GameLoading/Assets/1920x1080/girl_moon.png",
        "GameTask/GameLoading/Assets/1920x1080/welkin_moon_logo.png",
    ]

    var requiredDirectories: [URL] {
        [
            rootURL,
            userURL,
            userURL.appendingPathComponent("JsScript", isDirectory: true),
            userURL.appendingPathComponent("AutoPathing", isDirectory: true),
            userURL.appendingPathComponent("AutoFight", isDirectory: true),
            userURL.appendingPathComponent("AutoGeniusInvokation", isDirectory: true),
            userURL.appendingPathComponent("KeyMouseScript", isDirectory: true),
            userURL.appendingPathComponent("ScriptGroup", isDirectory: true),
            userURL.appendingPathComponent("OneDragon", isDirectory: true),
            userURL.appendingPathComponent("Subscriptions", isDirectory: true),
            userURL.appendingPathComponent("Temp", isDirectory: true),
            userURL
                .appendingPathComponent("Cache", isDirectory: true)
                .appendingPathComponent("MemoryFileCache", isDirectory: true),
            reposURL,
            cacheURL,
            downloadCacheURL,
            modelCacheURL,
            assetsURL,
            mapsURL,
            logURL,
            runURL
        ]
    }
}

struct BGIExternalResourcePackage: Identifiable, Equatable, Sendable {
    enum SourceKind: String, Sendable {
        case nuGetContentFiles
        case gitShallowClone
        case releaseArchive
        case httpCache
    }

    let id: String
    let version: String?
    let sourceKind: SourceKind
    let sourceDescription: String
    let localDirectory: String
    let requiredAssetPaths: [String]

    static let modelAssets = BGIExternalResourcePackage(
        id: "BetterGI.Assets.Model",
        version: "1.0.24",
        sourceKind: .nuGetContentFiles,
        sourceDescription: "BetterGI.Assets.Model NuGet contentFiles, or a macOS release archive with the same Assets/Model layout",
        localDirectory: "Assets/Model",
        requiredAssetPaths: BGIOnnxModel.upstreamRegisteredModels.map(\.assetPath)
    )

    static let mapAssets = BGIExternalResourcePackage(
        id: "BetterGI.Assets.Map",
        version: "1.0.19",
        sourceKind: .nuGetContentFiles,
        sourceDescription: "BetterGI.Assets.Map NuGet contentFiles, or a macOS release archive with the same Assets/Map layout",
        localDirectory: "Assets/Map",
        requiredAssetPaths: [
            "Assets/Map/Teyvat/city_info.json",
            "Assets/Map/Teyvat/City_701_color.webp",
            "Assets/Map/Teyvat/City_701_gray.webp"
        ]
    )

    static let scriptRepository = BGIExternalResourcePackage(
        id: "bettergi-scripts-list",
        version: nil,
        sourceKind: .gitShallowClone,
        sourceDescription: "Git shallow clone from CNB, GitCode, or GitHub bettergi-scripts-list mirror",
        localDirectory: "Repos/bettergi-scripts-list",
        requiredAssetPaths: [
            "Repos/bettergi-scripts-list/repo.json",
            "Repos/bettergi-scripts-list/repo/js",
            "Repos/bettergi-scripts-list/repo/pathing",
            "Repos/bettergi-scripts-list/repo/combat",
            "Repos/bettergi-scripts-list/repo/tcg"
        ]
    )

    static let firstLaunchPackages: [BGIExternalResourcePackage] = [
        .modelAssets,
        .mapAssets,
        .scriptRepository
    ]
}
