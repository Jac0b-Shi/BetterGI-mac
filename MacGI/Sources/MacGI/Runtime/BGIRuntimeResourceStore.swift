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
    }

    func synchronizeBundledGameTaskResources(
        sourceURL: URL? = Bundle.module.resourceURL?
            .appendingPathComponent("GameTask", isDirectory: true),
        fileManager: FileManager = .default
    ) throws {
        guard let sourceURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSFilePathErrorKey: "Bundle.module/GameTask"
            ])
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: sourceURL.path])
        }

        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let identifier = UUID().uuidString
        let stagingURL = rootURL.appendingPathComponent(".GameTask.staging-\(identifier)", isDirectory: true)
        let backupURL = rootURL.appendingPathComponent(".GameTask.backup-\(identifier)", isDirectory: true)
        let destinationURL = rootURL.appendingPathComponent("GameTask", isDirectory: true)
        defer {
            try? fileManager.removeItem(at: stagingURL)
            try? fileManager.removeItem(at: backupURL)
        }

        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)
        if destinationExists {
            try fileManager.moveItem(at: destinationURL, to: backupURL)
        }
        do {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            if destinationExists {
                try? fileManager.removeItem(at: backupURL)
            }
        } catch {
            if destinationExists, !fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw error
        }
    }

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
