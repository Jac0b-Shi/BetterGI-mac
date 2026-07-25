import Darwin
import CoreFoundation
import Foundation

enum BetterGICoreRPCError: Error, LocalizedError, Equatable {
    case socket(String)
    case protocolViolation(String)
    case remote(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .socket(let message): message
        case .protocolViolation(let message): message
        case .remote(let code, let message): "Core RPC \(code): \(message)"
        }
    }
}

struct BetterGICoreHandshake: Equatable, Sendable {
    let protocolVersion: Int
    let runtimeVersion: String
    let architecture: String
    let openCVVersion: String
    let clearScriptReady: Bool
    let capabilities: [String]
}

struct BetterGIScriptGroupProjectSummary: Equatable, Sendable, Identifiable {
    let index: Int
    let name: String
    let type: String
    let status: String
    let schedule: String
    let runNum: Int
    let folderName: String
    let hasCustomSettings: Bool
    let nextFlag: Bool

    var id: String { "\(index)|\(type)|\(name)" }
}

enum BetterGIJSONValue: Equatable, Sendable {
    case null
    case string(String)
    case bool(Bool)
    case strings([String])
    case integer(Int64)
    case number(Double)
    case array([BetterGIJSONValue])
    case object([String: BetterGIJSONValue])

    init(any: Any) throws {
        switch any {
        case is NSNull:
            self = .null
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as [String]:
            self = .strings(value)
        case let value as [Any]:
            self = .array(try value.map(Self.init(any:)))
        case let value as [String: Any]:
            self = .object(try value.mapValues(Self.init(any:)))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if CFNumberIsFloatType(value) {
                self = .number(value.doubleValue)
            } else {
                self = .integer(value.int64Value)
            }
        default:
            throw BetterGICoreRPCError.protocolViolation(
                "Unsupported JSON settings value: \(String(describing: type(of: any)))."
            )
        }
    }

    var any: Any {
        switch self {
        case .null: NSNull()
        case .string(let value): value
        case .bool(let value): value
        case .strings(let value): value
        case .integer(let value): value
        case .number(let value): value
        case .array(let value): value.map(\.any)
        case .object(let value): value.mapValues(\.any)
        }
    }
}

struct BetterGISettingItem: Equatable, Sendable, Identifiable {
    let name: String
    let type: String
    let label: String
    let options: [String]
    let cascadeOptions: [String: [String]]
    let defaultValue: BetterGIJSONValue?
    var id: String { "\(type)|\(name)|\(label)" }
}

struct BetterGIProjectCustomSettings: Equatable, Sendable {
    let projectIndex: Int
    let schema: [BetterGISettingItem]
    var values: [String: BetterGIJSONValue]
}

struct BetterGIProjectCommonSettings: Equatable, Sendable {
    let projectIndex: Int
    var status: String
    let isJavascript: Bool
    var allowJsNotification: Bool
    var allowJsHTTP: Bool
    let httpAllowedURLs: [String]
}

struct BetterGIAddCandidate: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let folderName: String
    let type: String
}

struct BetterGIPathingEntry: Equatable, Sendable, Identifiable {
    let id: String
    let parentID: String?
    let name: String
    let isDirectory: Bool
}

struct BetterGIPathingDetail: Equatable, Sendable {
    let id: String
    let name: String
    let description: String?
    let author: String?
    let version: String?
    let bgiVersion: String?
    let type: String
    let mapName: String
    let waypointCount: Int
    let tags: [String]
    let readme: String?
}

struct BetterGIPathingCondition: Equatable, Sendable, Identifiable {
    let id: UUID
    var subject: String
    var predicate: String
    var objects: [String]
    var result: String

    init(
        id: UUID = UUID(),
        subject: String,
        predicate: String = "包含",
        objects: [String] = [],
        result: String = ""
    ) {
        self.id = id
        self.subject = subject
        self.predicate = predicate
        self.objects = objects
        self.result = result
    }
}

struct BetterGIPathingConditionDefinition: Equatable, Sendable {
    let predicates: [String]
    let objects: [String]
    let results: [String]
    let description: String?
}

struct BetterGIPathingSettings: Equatable, Sendable {
    var partyConditions: [BetterGIPathingCondition]
    var avatarConditions: [BetterGIPathingCondition]
    var useGadgetIntervalMs: Int
    var autoEatEnabled: Bool
    var recoverTiming: String
    let partySubjects: [String]
    let avatarSubjects: [String]
    let avatarResults: [String]
    let definitions: [String: BetterGIPathingConditionDefinition]
}

struct BetterGIScriptRepositoryState: Equatable, Sendable {
    let available: Bool
    let repositoryPath: String
    let indexPath: String?
    let webIndexPath: String?
    let lastUpdated: String?
    let subscribedPaths: [String]
}

struct BetterGIScriptRepositoryUpdateResult: Equatable, Sendable {
    let status: String
    let channel: String
    let repositoryPath: String
    let indexPath: String
}

struct BetterGIScriptRepositoryBatchUpdateResult: Equatable, Sendable {
    let attemptedCount: Int
    let successCount: Int
    let failureCount: Int
    let failedPaths: [String]
    let subscribedPaths: [String]
}

enum BetterGISchedulerCatalogMutation: Sendable {
    case add(type: String, candidateIDs: [String], shellCommand: String?)
    case remove(projectIndex: Int, sameFolder: Bool)
    case clear
    case reverse
    case updatePathingFolders
    case setNext(projectIndex: Int)
}

struct BetterGIGroupConfigSettings: Equatable, Sendable {
    var enabled: Bool
    var autoPick: Bool
    var autoEat: Bool
    var autoSkip: Bool
    var autoFight: Bool
    var autoRun: Bool
    var defaultAtkBoostingDishName: String
    var defaultAdventurersDishName: String
    var defaultDefBoostingDishName: String
    var fightStrategyName: String
    var fightActionSchedulerByCd: String
    var fightFinishDetectEnabled: Bool
    var fightFastCheckEnabled: Bool
    var fightFastCheckParams: String
    var fightRotateFindEnemyEnabled: Bool
    var fightRotaryFactor: Int
    var fightCheckBeforeBurst: Bool
    var fightIsFirstCheck: Bool
    var fightCheckEndDelay: String
    var fightBeforeDetectDelay: String
    var fightGuardianAvatar: String
    var fightGuardianCombatSkip: Bool
    var fightBurstEnabled: Bool
    var fightGuardianAvatarHold: Bool
    var fightPickDropsAfterFightEnabled: Bool
    var fightPickDropsAfterFightSeconds: Int
    var fightKazuhaPickupEnabled: Bool
    var fightQinDoublePickUp: Bool
    var fightExpBasedPickupEnabled: Bool
    var fightBattleThresholdForLoot: Int?
    var fightOnlyPickEliteDropsMode: String
    var fightKazuhaPartyName: String
    var fightTimeout: Int
    var fightSwimmingEnabled: Bool
    var partyName: String
    var visitStatue: Bool
    var mainAvatar: String
    var guardianAvatar: String
    var guardianInterval: String
    var guardianLongPress: Bool
    var gadgetInterval: Int
    var recoverTiming: String
    var skipDuring: String
    var hideOnRepeat: Bool
    var hurryOnAvatar: String
    var travelMode: String
    var distance: Int
    var approachStopDistance: Int
    var switchToWalkEnabled: Bool
    var mwkJumpFlyEnabled: Bool
    var mwkJumpFlyIntervalSeconds: Double
    var taskCycleEnabled: Bool
    var taskCycleBoundaryTime: Int
    var taskCycleUsesServerTime: Bool
    var taskCycle: Int
    var taskCycleIndex: Int
    var completionSkipEnabled: Bool
    var completionSkipPolicy: String
    var completionBoundaryTime: Int
    var completionUsesServerTime: Bool
    var completionLastRunGapSeconds: Int
    var completionReferencePoint: String
    var priorityEnabled: Bool
    var priorityGroupNames: String
    var priorityMaxRetryCount: Int
    let avatarIndexOptions: [String]
    let hurryOnAvatarOptions: [String]
    let travelModeOptions: [String]
    let fightStrategyOptions: [String]
    let onlyPickEliteDropsModeOptions: [BetterGICoreNamedOption]
    let recoverTimingOptions: [BetterGICoreNamedOption]
    let completionSkipPolicyOptions: [BetterGICoreNamedOption]
    let completionReferencePointOptions: [BetterGICoreNamedOption]
    var enableShellConfig: Bool
    var shellDisable: Bool
    var shellTimeout: Int
    var shellNoWindow: Bool
    var shellOutput: Bool
}

struct BetterGIScriptGroupSummary: Equatable, Sendable, Identifiable {
    let name: String
    let path: String
    let index: Int
    let hideOnRepeat: Bool
    let projects: [BetterGIScriptGroupProjectSummary]

    var id: String { "\(index)|\(name)" }
}

struct BetterGIScriptProjectSummary: Equatable, Sendable, Identifiable {
    let folderName: String
    let name: String
    let version: String

    var id: String { folderName }
}

/// Blocking request/response transport. Call it from a worker task, never the main actor.
final class BetterGICoreRPCClient: @unchecked Sendable {
    static let protocolVersion = 1
    static let maximumFrameLength = 16 * 1024 * 1024

    private let socketPath: String
    private let sessionToken: String
    private let lock = NSLock()
    private var descriptor: Int32 = -1

    init(socketPath: String, sessionToken: String) {
        self.socketPath = socketPath
        self.sessionToken = sessionToken
    }

    deinit { disconnect() }

    func connect() throws {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor < 0 else { return }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw posixError("socket") }
        do {
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(socketPath.utf8CString)
            let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
            guard pathBytes.count <= pathCapacity else {
                throw BetterGICoreRPCError.socket("Core socket path exceeds sockaddr_un capacity.")
            }
            _ = withUnsafeMutablePointer(to: &address.sun_path) { target in
                pathBytes.withUnsafeBytes { source in
                    memcpy(target, source.baseAddress!, pathBytes.count)
                }
            }
            let length = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, length)
                }
            }
            guard result == 0 else { throw posixError("connect") }
            descriptor = fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    func handshake() throws -> BetterGICoreHandshake {
        guard let result = try request(method: "core.handshake") as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid core.handshake result.")
        }
        guard
            let version = result["protocolVersion"] as? Int,
            let runtime = result["runtimeVersion"] as? String,
            let architecture = result["architecture"] as? String,
            let openCV = result["openCvVersion"] as? String,
            let clearScript = result["clearScriptReady"] as? Bool,
            let capabilities = result["capabilities"] as? [String]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid core.handshake result.") }
        guard version == Self.protocolVersion else {
            throw BetterGICoreRPCError.protocolViolation(
                "Protocol mismatch: Swift=\(Self.protocolVersion), Core=\(version)."
            )
        }
        return BetterGICoreHandshake(
            protocolVersion: version,
            runtimeVersion: runtime,
            architecture: architecture,
            openCVVersion: openCV,
            clearScriptReady: clearScript,
            capabilities: capabilities
        )
    }

    func initialize(
        runtimeRoot: URL,
        serverTimeZoneOffsetHours: Double,
        mapMatchingMethod: String
    ) throws -> [String: Any] {
        guard let result = try request(
            method: "core.initialize",
            parameters: [
                "runtimeRoot": runtimeRoot.path,
                "serverTimeZoneOffsetHours": serverTimeZoneOffsetHours,
                "mapMatchingMethod": mapMatchingMethod,
            ]
        ) as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid core.initialize result.")
        }
        return result
    }

    func listScriptGroups() throws -> [BetterGIScriptGroupSummary] {
        guard let items = try request(method: "catalog.listScriptGroups") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script-group catalog result.")
        }
        return try items.map { item in
            guard let name = item["name"] as? String,
                  let path = item["path"] as? String,
                  let index = item["index"] as? Int,
                  let hideOnRepeat = item["hideOnRepeat"] as? Bool,
                  let projectItems = item["projects"] as? [[String: Any]]
            else {
                throw BetterGICoreRPCError.protocolViolation("Invalid script-group summary.")
            }
            let projects = try projectItems.map { project -> BetterGIScriptGroupProjectSummary in
                guard let projectIndex = project["index"] as? Int,
                      let projectName = project["name"] as? String,
                      let type = project["type"] as? String,
                      let status = project["status"] as? String,
                      let schedule = project["schedule"] as? String,
                      let runNum = project["runNum"] as? Int,
                      let folderName = project["folderName"] as? String,
                      let hasCustomSettings = project["hasCustomSettings"] as? Bool,
                      let nextFlag = project["nextFlag"] as? Bool
                else { throw BetterGICoreRPCError.protocolViolation("Invalid script-group project summary.") }
                return BetterGIScriptGroupProjectSummary(
                    index: projectIndex,
                    name: projectName,
                    type: type,
                    status: status,
                    schedule: schedule,
                    runNum: runNum,
                    folderName: folderName,
                    hasCustomSettings: hasCustomSettings,
                    nextFlag: nextFlag
                )
            }
            return BetterGIScriptGroupSummary(
                name: name,
                path: path,
                index: index,
                hideOnRepeat: hideOnRepeat,
                projects: projects
            )
        }
    }

    func projectCommonSettings(groupName: String, projectIndex: Int) throws -> BetterGIProjectCommonSettings {
        guard let item = try request(method: "catalog.getScriptGroupProjectCommonSettings", parameters: [
            "name": groupName, "projectIndex": projectIndex
        ]) as? [String: Any],
              let index = item["index"] as? Int,
              let status = item["status"] as? String,
              let isJavascript = item["isJavascript"] as? Bool,
              let allowHTTP = item["allowJsHttp"] as? Bool,
              let urls = item["httpAllowedUrls"] as? [String]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid project common settings.") }
        return BetterGIProjectCommonSettings(
            projectIndex: index, status: status, isJavascript: isJavascript,
            allowJsNotification: item["allowJsNotification"] as? Bool ?? true,
            allowJsHTTP: allowHTTP, httpAllowedURLs: urls)
    }

    func projectCustomSettings(groupName: String, projectIndex: Int) throws -> BetterGIProjectCustomSettings {
        guard let item = try request(method: "catalog.getScriptGroupProjectCustomSettings", parameters: [
            "name": groupName, "projectIndex": projectIndex
        ]) as? [String: Any], let index = item["index"] as? Int,
              let schemaItems = item["schema"] as? [[String: Any]],
              let rawValues = item["values"] as? [String: Any]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid project custom settings.") }
        let schema = try schemaItems.map { raw -> BetterGISettingItem in
            guard let name = raw["name"] as? String, let type = raw["type"] as? String,
                  let label = raw["label"] as? String
            else { throw BetterGICoreRPCError.protocolViolation("Invalid custom setting schema.") }
            let defaultValue = try raw["default"].map(BetterGIJSONValue.init(any:))
            return BetterGISettingItem(name: name, type: type, label: label,
                options: raw["options"] as? [String] ?? [],
                cascadeOptions: raw["cascadeOptions"] as? [String: [String]] ?? [:],
                defaultValue: defaultValue)
        }
        let values = try rawValues.mapValues(BetterGIJSONValue.init(any:))
        return BetterGIProjectCustomSettings(projectIndex: index, schema: schema, values: values)
    }

    func listAddCandidates(type: String) throws -> [BetterGIAddCandidate] {
        guard let items = try request(method: "catalog.listScriptGroupAddCandidates", parameters: ["type": type]) as? [[String: Any]]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid add-candidate catalog.") }
        return try items.map { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String,
                  let folder = item["folderName"] as? String, let type = item["type"] as? String
            else { throw BetterGICoreRPCError.protocolViolation("Invalid add candidate.") }
            return BetterGIAddCandidate(id: id, name: name, folderName: folder, type: type)
        }
    }

    func listPathingEntries() throws -> [BetterGIPathingEntry] {
        guard let items = try request(method: "pathing.list") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid pathing catalog result.")
        }
        return try items.map { item in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let isDirectory = item["isDirectory"] as? Bool
            else {
                throw BetterGICoreRPCError.protocolViolation("Invalid pathing catalog entry.")
            }
            return BetterGIPathingEntry(
                id: id,
                parentID: item["parentId"] as? String,
                name: name,
                isDirectory: isDirectory)
        }
    }

    func pathingDetail(id: String) throws -> BetterGIPathingDetail {
        guard let item = try request(
            method: "pathing.detail",
            parameters: ["id": id]
        ) as? [String: Any],
              let resultID = item["id"] as? String,
              let name = item["name"] as? String,
              let type = item["type"] as? String,
              let mapName = item["mapName"] as? String,
              let waypointCount = item["waypointCount"] as? Int,
              let tags = item["tags"] as? [String]
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid pathing detail result.")
        }
        return BetterGIPathingDetail(
            id: resultID,
            name: name,
            description: item["description"] as? String,
            author: item["author"] as? String,
            version: item["version"] as? String,
            bgiVersion: item["bgiVersion"] as? String,
            type: type,
            mapName: mapName,
            waypointCount: waypointCount,
            tags: tags,
            readme: item["readme"] as? String)
    }

    func pathingSettings() throws -> BetterGIPathingSettings {
        guard let item = try request(method: "pathing.settings.get") as? [String: Any]
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid pathing settings result.")
        }
        return try Self.decodePathingSettings(item)
    }

    func savePathingSettings(_ settings: BetterGIPathingSettings) throws -> BetterGIPathingSettings {
        let encodeConditions: ([BetterGIPathingCondition]) -> [[String: Any]] = { conditions in
            conditions.map {
                [
                    "subject": $0.subject,
                    "predicate": $0.predicate,
                    "objects": $0.objects,
                    "result": $0.result,
                ]
            }
        }
        guard let item = try request(
            method: "pathing.settings.save",
            parameters: ["settings": [
                "partyConditions": encodeConditions(settings.partyConditions),
                "avatarConditions": encodeConditions(settings.avatarConditions),
                "useGadgetIntervalMs": settings.useGadgetIntervalMs,
                "autoEatEnabled": settings.autoEatEnabled,
                "recoverTiming": settings.recoverTiming,
            ]]
        ) as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid saved pathing settings result.")
        }
        return try Self.decodePathingSettings(item)
    }

    private static func decodePathingSettings(
        _ item: [String: Any]
    ) throws -> BetterGIPathingSettings {
        guard let rawParty = item["partyConditions"] as? [[String: Any]],
              let rawAvatars = item["avatarConditions"] as? [[String: Any]],
              let useGadgetIntervalMs = item["useGadgetIntervalMs"] as? Int,
              let autoEatEnabled = item["autoEatEnabled"] as? Bool,
              let recoverTiming = item["recoverTiming"] as? String,
              let partySubjects = item["partySubjects"] as? [String],
              let avatarSubjects = item["avatarSubjects"] as? [String],
              let avatarResults = item["avatarResults"] as? [String],
              let rawDefinitions = item["definitions"] as? [String: [String: Any]]
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid pathing settings fields.")
        }
        let decodeCondition: ([String: Any]) throws -> BetterGIPathingCondition = { value in
            guard let subject = value["subject"] as? String,
                  let predicate = value["predicate"] as? String,
                  let objects = value["objects"] as? [String],
                  let result = value["result"] as? String
            else {
                throw BetterGICoreRPCError.protocolViolation("Invalid pathing condition.")
            }
            return BetterGIPathingCondition(
                subject: subject,
                predicate: predicate,
                objects: objects,
                result: result)
        }
        let definitions = try rawDefinitions.mapValues { value in
            guard let predicates = value["predicates"] as? [String],
                  let objects = value["objects"] as? [String],
                  let results = value["results"] as? [String]
            else {
                throw BetterGICoreRPCError.protocolViolation(
                    "Invalid pathing condition definition.")
            }
            return BetterGIPathingConditionDefinition(
                predicates: predicates,
                objects: objects,
                results: results,
                description: value["description"] as? String)
        }
        return BetterGIPathingSettings(
            partyConditions: try rawParty.map(decodeCondition),
            avatarConditions: try rawAvatars.map(decodeCondition),
            useGadgetIntervalMs: useGadgetIntervalMs,
            autoEatEnabled: autoEatEnabled,
            recoverTiming: recoverTiming,
            partySubjects: partySubjects,
            avatarSubjects: avatarSubjects,
            avatarResults: avatarResults,
            definitions: definitions)
    }

    func listScriptProjects() throws -> [BetterGIScriptProjectSummary] {
        guard let items = try request(method: "catalog.listScriptProjects") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script-project catalog result.")
        }
        return try items.map { item in
            guard let folderName = item["folderName"] as? String,
                  let name = item["name"] as? String,
                  let version = item["version"] as? String
            else { throw BetterGICoreRPCError.protocolViolation("Invalid script-project summary.") }
            return BetterGIScriptProjectSummary(folderName: folderName, name: name, version: version)
        }
    }

    func scriptProjectRootLocation() throws -> String {
        guard let result = try request(method: "catalog.getScriptProjectRootLocation") as? [String: Any],
              let path = result["path"] as? String
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script project root location.")
        }
        return path
    }

    func scriptRepositoryState() throws -> BetterGIScriptRepositoryState {
        guard let item = try request(method: "repository.state") as? [String: Any],
              let available = item["available"] as? Bool,
              let repositoryPath = item["repositoryPath"] as? String,
              let subscribedPaths = item["subscribedPaths"] as? [String]
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script repository state.")
        }
        return BetterGIScriptRepositoryState(
            available: available,
            repositoryPath: repositoryPath,
            indexPath: item["indexPath"] as? String,
            webIndexPath: item["webIndexPath"] as? String,
            lastUpdated: item["lastUpdated"] as? String,
            subscribedPaths: subscribedPaths
        )
    }

    func updateScriptRepository(channel: String, url: String) throws -> BetterGIScriptRepositoryUpdateResult {
        guard let item = try request(
            method: "repository.update",
            parameters: ["channel": channel, "url": url]
        ) as? [String: Any],
              let status = item["status"] as? String,
              let resultChannel = item["channel"] as? String,
              let repositoryPath = item["repositoryPath"] as? String,
              let indexPath = item["indexPath"] as? String
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script repository update result.")
        }
        return BetterGIScriptRepositoryUpdateResult(
            status: status,
            channel: resultChannel,
            repositoryPath: repositoryPath,
            indexPath: indexPath
        )
    }

    func updateSubscribedScripts(
        channel: String,
        url: String
    ) throws -> BetterGIScriptRepositoryBatchUpdateResult {
        guard let item = try request(
            method: "repository.updateSubscribed",
            parameters: ["channel": channel, "url": url]
        ) as? [String: Any],
              let attemptedCount = item["attemptedCount"] as? Int,
              let successCount = item["successCount"] as? Int,
              let failureCount = item["failureCount"] as? Int,
              let failedPaths = item["failedPaths"] as? [String],
              let subscribedPaths = item["subscribedPaths"] as? [String]
        else {
            throw BetterGICoreRPCError.protocolViolation(
                "Invalid repository.updateSubscribed result."
            )
        }
        return BetterGIScriptRepositoryBatchUpdateResult(
            attemptedCount: attemptedCount,
            successCount: successCount,
            failureCount: failureCount,
            failedPaths: failedPaths,
            subscribedPaths: subscribedPaths
        )
    }

    func resetScriptRepository() throws {
        guard let item = try request(method: "repository.reset") as? [String: Any],
              item["reset"] as? Bool == true
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid script repository reset result.")
        }
    }

    func scriptRepositoryWebString(method: String, parameters: [String: Any]? = nil) throws -> String {
        guard let result = try request(method: method, parameters: parameters) as? String else {
            throw BetterGICoreRPCError.protocolViolation("Invalid \(method) result.")
        }
        return result
    }

    func scriptRepositoryWebBool(method: String, parameters: [String: Any]? = nil) throws -> Bool {
        guard let result = try request(method: method, parameters: parameters) as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid \(method) result.")
        }
        return result
    }

    func importScriptRepositoryURI(_ uri: String) throws -> Int {
        guard let result = try request(
            method: "repository.web.importUri",
            parameters: ["uri": uri]
        ) as? [String: Any],
              let installedCount = result["installedCount"] as? Int
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid repository import result.")
        }
        return installedCount
    }

    @discardableResult
    func request(method: String, parameters: [String: Any]? = nil) throws -> Any {
        lock.lock()
        defer { lock.unlock() }
        guard descriptor >= 0 else { throw BetterGICoreRPCError.socket("Core RPC is not connected.") }
        let id = UUID().uuidString
        var envelope: [String: Any] = [
            "id": id,
            "method": method,
            "sessionToken": sessionToken
        ]
        if let parameters { envelope["params"] = parameters }
        let body = try JSONSerialization.data(withJSONObject: envelope)
        guard body.count <= Self.maximumFrameLength else {
            throw BetterGICoreRPCError.protocolViolation("RPC request frame is too large.")
        }
        var length = UInt32(body.count).littleEndian
        try withUnsafeBytes(of: &length) { try writeAll($0) }
        try body.withUnsafeBytes { try writeAll($0) }

        let header = try readExactly(count: 4)
        let responseLength = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard responseLength > 0, responseLength <= Self.maximumFrameLength else {
            throw BetterGICoreRPCError.protocolViolation("Invalid RPC response frame length \(responseLength).")
        }
        let responseData = try readExactly(count: Int(responseLength))
        guard
            let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            response["id"] as? String == id
        else { throw BetterGICoreRPCError.protocolViolation("RPC response id does not match request.") }
        if let error = response["error"] as? [String: Any] {
            throw BetterGICoreRPCError.remote(
                code: error["code"] as? String ?? "Unknown",
                message: error["message"] as? String ?? "Core returned an error without a message."
            )
        }
        guard let result = response["result"] else {
            throw BetterGICoreRPCError.protocolViolation("RPC response has neither result nor error.")
        }
        return result
    }

    private func writeAll(_ bytes: UnsafeRawBufferPointer) throws {
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
            guard count > 0 else { throw posixError("write") }
            offset += count
        }
    }

    private func readExactly(count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let received = Darwin.read(descriptor, bytes.baseAddress!.advanced(by: offset), count - offset)
                guard received > 0 else {
                    throw BetterGICoreRPCError.socket("Core RPC disconnected while reading a frame.")
                }
                offset += received
            }
        }
        return data
    }

    private func posixError(_ operation: String) -> BetterGICoreRPCError {
        BetterGICoreRPCError.socket("\(operation) failed: \(String(cString: strerror(errno)))")
    }
}
