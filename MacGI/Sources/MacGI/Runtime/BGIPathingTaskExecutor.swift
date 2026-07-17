import Foundation

struct BGIPathingMaterialInfo: Equatable, Codable, Sendable {
    var monster: String?
    var material: String?
    var count: String?

    init(monster: String? = nil, material: String? = nil, count: String? = nil) {
        self.monster = monster
        self.material = material
        self.count = count
    }
}

struct BGIPathingTaskInfo: Equatable, Codable, Sendable {
    var name: String
    var description: String?
    var author: String?
    var version: String?
    var bgiVersion: String?
    var type: String
    var order: Int
    var tags: [String]
    var enableMonsterLootSplit: Bool
    var mapName: String
    var mapMatchMethod: String
    var items: [BGIPathingMaterialInfo]

    init(
        name: String = "",
        description: String? = nil,
        author: String? = nil,
        version: String? = nil,
        bgiVersion: String? = nil,
        type: String = "",
        order: Int = 0,
        tags: [String] = [],
        enableMonsterLootSplit: Bool = false,
        mapName: String = "Teyvat",
        mapMatchMethod: String = "TemplateMatch",
        items: [BGIPathingMaterialInfo] = []
    ) {
        self.name = name
        self.description = description
        self.author = author
        self.version = version
        self.bgiVersion = bgiVersion
        self.type = type
        self.order = order
        self.tags = tags
        self.enableMonsterLootSplit = enableMonsterLootSplit
        self.mapName = mapName
        self.mapMatchMethod = mapMatchMethod
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        bgiVersion = try container.decodeIfPresent(String.self, forKey: .bgiVersion)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        order = try container.decodeIfPresent(Int.self, forKey: .order) ?? 0
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        enableMonsterLootSplit = try container.decodeIfPresent(Bool.self, forKey: .enableMonsterLootSplit) ?? false
        mapName = try container.decodeIfPresent(String.self, forKey: .mapName) ?? "Teyvat"
        mapMatchMethod = try container.decodeIfPresent(String.self, forKey: .mapMatchMethod) ?? "TemplateMatch"
        items = try container.decodeIfPresent([BGIPathingMaterialInfo].self, forKey: .items) ?? []
    }
}

struct BGIPathingTaskConfig: Equatable, Codable, Sendable {
    var realtimeTriggers: [String: Bool]

    init(realtimeTriggers: [String: Bool] = ["AutoPick": true]) {
        self.realtimeTriggers = realtimeTriggers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        realtimeTriggers = try container.decodeIfPresent([String: Bool].self, forKey: .realtimeTriggers)
            ?? ["AutoPick": true]
    }
}

struct BGIPathingFarmingSession: Equatable, Codable, Sendable {
    var allowFarmingCount: Bool
    var normalMobCount: Double
    var eliteMobCount: Double
    var primaryTarget: String
    var durationSeconds: Double
    var eliteDetails: String
    var totalMora: Double

    init(
        allowFarmingCount: Bool = false,
        normalMobCount: Double = 0,
        eliteMobCount: Double = 0,
        primaryTarget: String = "",
        durationSeconds: Double = 0,
        eliteDetails: String = "",
        totalMora: Double = 0
    ) {
        self.allowFarmingCount = allowFarmingCount
        self.normalMobCount = normalMobCount
        self.eliteMobCount = eliteMobCount
        self.primaryTarget = primaryTarget
        self.durationSeconds = durationSeconds
        self.eliteDetails = eliteDetails
        self.totalMora = totalMora
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        allowFarmingCount = try container.decodeIfPresent(Bool.self, forKey: .allowFarmingCount) ?? false
        normalMobCount = try container.decodeIfPresent(Double.self, forKey: .normalMobCount) ?? 0
        eliteMobCount = try container.decodeIfPresent(Double.self, forKey: .eliteMobCount) ?? 0
        primaryTarget = try container.decodeIfPresent(String.self, forKey: .primaryTarget) ?? ""
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        eliteDetails = try container.decodeIfPresent(String.self, forKey: .eliteDetails) ?? ""
        totalMora = try container.decodeIfPresent(Double.self, forKey: .totalMora) ?? 0
    }
}

struct BGIPathingMisidentification: Equatable, Codable, Sendable {
    var type: [String]
    var handlingMode: String
    var arrivalTime: Int

    init(
        type: [String] = ["unrecognized"],
        handlingMode: String = "previousDetectedPoint",
        arrivalTime: Int = 0
    ) {
        self.type = type
        self.handlingMode = handlingMode
        self.arrivalTime = arrivalTime
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent([String].self, forKey: .type) ?? ["unrecognized"]
        handlingMode = try container.decodeIfPresent(String.self, forKey: .handlingMode) ?? "previousDetectedPoint"
        arrivalTime = try container.decodeIfPresent(Int.self, forKey: .arrivalTime) ?? 0
    }
}

struct BGIPathingWaypointExtParams: Equatable, Codable, Sendable {
    var misidentification: BGIPathingMisidentification
    var description: String
    var monsterTag: String?
    var enableMonsterLootSplit: Bool

    init(
        misidentification: BGIPathingMisidentification = BGIPathingMisidentification(),
        description: String = "",
        monsterTag: String? = nil,
        enableMonsterLootSplit: Bool = false
    ) {
        self.misidentification = misidentification
        self.description = description
        self.monsterTag = monsterTag
        self.enableMonsterLootSplit = enableMonsterLootSplit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        misidentification = try container.decodeIfPresent(BGIPathingMisidentification.self, forKey: .misidentification)
            ?? BGIPathingMisidentification()
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        monsterTag = try container.decodeIfPresent(String.self, forKey: .monsterTag)
        enableMonsterLootSplit = try container.decodeIfPresent(Bool.self, forKey: .enableMonsterLootSplit) ?? false
    }
}

struct BGIPathingWaypoint: Equatable, Codable, Sendable {
    var x: Double
    var y: Double
    var pointExtParams: BGIPathingWaypointExtParams
    var type: String
    var moveMode: String
    var action: String?
    var actionParams: String?
    var items: [BGIPathingMaterialInfo]

    init(
        x: Double = 0,
        y: Double = 0,
        pointExtParams: BGIPathingWaypointExtParams = BGIPathingWaypointExtParams(),
        type: String = BGIPathingWaypointType.path,
        moveMode: String = BGIPathingMoveMode.walk,
        action: String? = nil,
        actionParams: String? = nil,
        items: [BGIPathingMaterialInfo] = []
    ) {
        self.x = x
        self.y = y
        self.pointExtParams = pointExtParams
        self.type = type
        self.moveMode = moveMode
        self.action = action
        self.actionParams = actionParams
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
        pointExtParams = try container.decodeIfPresent(BGIPathingWaypointExtParams.self, forKey: .pointExtParams)
            ?? BGIPathingWaypointExtParams()
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? BGIPathingWaypointType.path
        moveMode = try container.decodeIfPresent(String.self, forKey: .moveMode) ?? BGIPathingMoveMode.walk
        action = try container.decodeIfPresent(String.self, forKey: .action)
        actionParams = try container.decodeIfPresent(String.self, forKey: .actionParams)
        items = try container.decodeIfPresent([BGIPathingMaterialInfo].self, forKey: .items) ?? []
    }
}

struct BGIPathingTask: Equatable, Codable, Sendable {
    var fileName: String
    var fullPath: String
    var info: BGIPathingTaskInfo
    var config: BGIPathingTaskConfig
    var farmingInfo: BGIPathingFarmingSession
    var positions: [BGIPathingWaypoint]

    init(
        fileName: String = "",
        fullPath: String = "",
        info: BGIPathingTaskInfo = BGIPathingTaskInfo(),
        config: BGIPathingTaskConfig = BGIPathingTaskConfig(),
        farmingInfo: BGIPathingFarmingSession = BGIPathingFarmingSession(),
        positions: [BGIPathingWaypoint] = []
    ) {
        self.fileName = fileName
        self.fullPath = fullPath
        self.info = info
        self.config = config
        self.farmingInfo = farmingInfo
        self.positions = positions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fullPath = try container.decodeIfPresent(String.self, forKey: .fullPath) ?? ""
        info = try container.decodeIfPresent(BGIPathingTaskInfo.self, forKey: .info) ?? BGIPathingTaskInfo()
        config = try container.decodeIfPresent(BGIPathingTaskConfig.self, forKey: .config) ?? BGIPathingTaskConfig()
        farmingInfo = try container.decodeIfPresent(BGIPathingFarmingSession.self, forKey: .farmingInfo)
            ?? BGIPathingFarmingSession()
        positions = try container.decodeIfPresent([BGIPathingWaypoint].self, forKey: .positions) ?? []
    }

    func hasAction(_ actionName: String) -> Bool {
        positions.contains { $0.action == actionName }
    }
}

enum BGIPathingTaskType {
    static let collect = "collect"
    static let mining = "mining"
    static let farming = "farming"
}

enum BGIPathingWaypointType {
    static let path = "path"
    static let target = "target"
    static let teleport = "teleport"
    static let orientation = "orientation"
}

enum BGIPathingMoveMode {
    static let walk = "walk"
    static let run = "run"
    static let dash = "dash"
    static let climb = "climb"
    static let fly = "fly"
    static let jump = "jump"
    static let swim = "swim"
}

enum BGIPathingAction {
    static let stopFlying = "stop_flying"
    static let forceTp = "force_tp"
    static let nahidaCollect = "nahida_collect"
    static let pickAround = "pick_around"
    static let fight = "fight"
    static let upDownGrabLeaf = "up_down_grab_leaf"
    static let hydroCollect = "hydro_collect"
    static let electroCollect = "electro_collect"
    static let anemoCollect = "anemo_collect"
    static let pyroCollect = "pyro_collect"
    static let combatScript = "combat_script"
    static let mining = "mining"
    static let linneaMining = "linnea_mining"
    static let logOutput = "log_output"
    static let fishing = "fishing"
    static let exitAndRelogin = "exit_and_relogin"
    static let wonderlandCycle = "wonderland_cycle"
    static let setTime = "set_time"
    static let useGadget = "use_gadget"
    static let pickUpCollect = "pick_up_collect"
}

enum BGIPathingActionWaypointUsage: Equatable, Sendable {
    case custom
    case path
    case target
}

enum BGIPathingNavigationPhase: String, Equatable, Sendable {
    case initialize
    case switchPartyBefore
    case validateGameWithTask
    case warmUpNavigation
    case segmentBegin
    case setPreviousPosition
    case waypointBegin
    case recoverWhenLowHp
    case teleport
    case beforeMoveToTarget
    case faceTo
    case moveTo
    case beforeMoveCloseToTarget
    case moveCloseTo
    case afterMoveToTarget
    case releaseInputs
}

struct BGIPathingWaypointForTrack: Equatable, Sendable {
    var source: BGIPathingWaypoint
    var gameX: Double
    var gameY: Double
    var mapName: String
    var mapMatchMethod: String

    var type: String { source.type }
    var moveMode: String { source.moveMode }
    var action: String? { source.action }
    var actionParams: String? { source.actionParams }
    var pointExtParams: BGIPathingWaypointExtParams { source.pointExtParams }

    init(waypoint: BGIPathingWaypoint, task: BGIPathingTask) {
        source = waypoint
        gameX = waypoint.x
        gameY = waypoint.y
        mapName = task.info.mapName
        mapMatchMethod = task.info.mapMatchMethod
    }
}

struct BGIPathingNavigationEvent: Equatable, Sendable {
    var phase: BGIPathingNavigationPhase
    var segmentIndex: Int?
    var waypointIndex: Int?
    var waypointType: String?
    var action: String?
}

struct BGIPathExecutorResult: Equatable, Sendable {
    var successEnd: Bool
    var successFight: Int
    var segmentCount: Int
    var waypointCount: Int
    var events: [BGIPathingNavigationEvent]
}

enum BGIPathExecutorError: LocalizedError, Equatable {
    case emptyPath
    case preconditionFailed(String)
    case navigationBackendUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            "BetterGI pathing task has no waypoints"
        case let .preconditionFailed(message):
            message
        case .navigationBackendUnavailable:
            "BetterGI pathing navigation backend is not available yet"
        }
    }
}

protocol BGIPathingNavigationBackend: AnyObject, Sendable {
    func switchPartyBefore(task: BGIPathingTask) async throws -> Bool
    func validateGameWithTask(task: BGIPathingTask) async throws -> Bool
    func initializePathing(task: BGIPathingTask) async throws
    func warmUpNavigation(mapMatchMethod: String) async throws
    func setPreviousPosition(_ waypoint: BGIPathingWaypointForTrack) async throws
    func recoverWhenLowHp(_ waypoint: BGIPathingWaypointForTrack) async throws
    func handleTeleportWaypoint(_ waypoint: BGIPathingWaypointForTrack, force: Bool) async throws
    func beforeMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws
    func faceTo(_ waypoint: BGIPathingWaypointForTrack) async throws
    func moveTo(_ waypoint: BGIPathingWaypointForTrack) async throws
    func beforeMoveCloseToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws
    func moveCloseTo(_ waypoint: BGIPathingWaypointForTrack) async throws
    func afterMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws
    func releaseAllInputs() async
}

final class BGIUnavailablePathingNavigationBackend: BGIPathingNavigationBackend {
    func switchPartyBefore(task: BGIPathingTask) async throws -> Bool {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func validateGameWithTask(task: BGIPathingTask) async throws -> Bool {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func initializePathing(task: BGIPathingTask) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func warmUpNavigation(mapMatchMethod: String) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func setPreviousPosition(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func recoverWhenLowHp(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func handleTeleportWaypoint(_ waypoint: BGIPathingWaypointForTrack, force: Bool) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func beforeMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func faceTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func moveTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func beforeMoveCloseToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func moveCloseTo(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func afterMoveToTarget(_ waypoint: BGIPathingWaypointForTrack) async throws {
        throw BGIPathExecutorError.navigationBackendUnavailable
    }

    func releaseAllInputs() async {}
}

final class BGIPathExecutor {
    private static let retryTimes = 2
    private let backend: BGIPathingNavigationBackend

    init(backend: BGIPathingNavigationBackend) {
        self.backend = backend
    }

    func pathing(_ task: BGIPathingTask) async throws -> BGIPathExecutorResult {
        guard !task.positions.isEmpty else {
            throw BGIPathExecutorError.emptyPath
        }

        var events: [BGIPathingNavigationEvent] = []

        events.append(event(.switchPartyBefore))
        guard try await backend.switchPartyBefore(task: task) else {
            throw BGIPathExecutorError.preconditionFailed("Pathing party switch failed")
        }

        events.append(event(.validateGameWithTask))
        guard try await backend.validateGameWithTask(task: task) else {
            throw BGIPathExecutorError.preconditionFailed("Pathing game validation failed")
        }

        events.append(event(.initialize))
        try await backend.initializePathing(task: task)

        let segments = Self.convertWaypointsForTrack(task)

        events.append(event(.warmUpNavigation))
        try await backend.warmUpNavigation(mapMatchMethod: task.info.mapMatchMethod)

        var successFight = 0
        var successEnd = false
        var visitedWaypointCount = 0

        for segmentIndex in segments.indices {
            let segment = segments[segmentIndex]
            events.append(event(.segmentBegin, segmentIndex: segmentIndex))

            var completedSegment = false
            for _ in 0..<Self.retryTimes {
                do {
                    if let first = segment.first, first.type != BGIPathingWaypointType.teleport {
                        events.append(event(.setPreviousPosition, segmentIndex: segmentIndex, waypointIndex: 0, waypoint: first))
                        try await backend.setPreviousPosition(first)
                    }

                    for waypointIndex in segment.indices {
                        let waypoint = segment[waypointIndex]
                        events.append(event(.waypointBegin, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                        events.append(event(.recoverWhenLowHp, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                        try await backend.recoverWhenLowHp(waypoint)

                        if waypoint.type == BGIPathingWaypointType.teleport {
                            events.append(event(.teleport, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                            try await backend.handleTeleportWaypoint(
                                waypoint,
                                force: waypoint.action == BGIPathingAction.forceTp
                            )
                        } else {
                            events.append(event(.beforeMoveToTarget, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                            try await backend.beforeMoveToTarget(waypoint)

                            if waypoint.type == BGIPathingWaypointType.orientation {
                                events.append(event(.faceTo, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                                try await backend.faceTo(waypoint)
                            } else if waypoint.action != BGIPathingAction.upDownGrabLeaf {
                                events.append(event(.moveTo, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                                try await backend.moveTo(waypoint)
                            }

                            events.append(event(.beforeMoveCloseToTarget, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                            try await backend.beforeMoveCloseToTarget(waypoint)

                            if Self.isTargetPoint(waypoint) {
                                events.append(event(.moveCloseTo, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                                try await backend.moveCloseTo(waypoint)
                            }

                            if Self.shouldRunAfterAction(waypoint) {
                                events.append(event(.afterMoveToTarget, segmentIndex: segmentIndex, waypointIndex: waypointIndex, waypoint: waypoint))
                                try await backend.afterMoveToTarget(waypoint)
                                if waypoint.action == BGIPathingAction.fight {
                                    successFight += 1
                                }
                            }
                        }

                        visitedWaypointCount += 1
                    }

                    completedSegment = true
                    break
                } catch {
                    events.append(event(.releaseInputs, segmentIndex: segmentIndex))
                    await backend.releaseAllInputs()
                    throw error
                }
            }

            if completedSegment, segmentIndex == segments.indices.last {
                successEnd = true
            }
        }

        events.append(event(.releaseInputs))
        await backend.releaseAllInputs()

        return BGIPathExecutorResult(
            successEnd: successEnd,
            successFight: successFight,
            segmentCount: segments.count,
            waypointCount: visitedWaypointCount,
            events: events
        )
    }

    static func convertWaypointsForTrack(_ task: BGIPathingTask) -> [[BGIPathingWaypointForTrack]] {
        let all = task.positions.map { BGIPathingWaypointForTrack(waypoint: $0, task: task) }
        var result: [[BGIPathingWaypointForTrack]] = []
        var current: [BGIPathingWaypointForTrack] = []

        for waypoint in all {
            if waypoint.type == BGIPathingWaypointType.teleport, !current.isEmpty {
                result.append(current)
                current = []
            }
            current.append(waypoint)
        }

        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    static func isTargetPoint(_ waypoint: BGIPathingWaypointForTrack) -> Bool {
        if waypoint.type == BGIPathingWaypointType.orientation || waypoint.action == BGIPathingAction.upDownGrabLeaf {
            return false
        }

        if let action = waypoint.action, let usage = actionWaypointUsage(action) {
            return usage == .target
        }

        return waypoint.type == BGIPathingWaypointType.target
    }

    static func actionWaypointUsage(_ action: String) -> BGIPathingActionWaypointUsage? {
        switch action {
        case BGIPathingAction.fight:
            return .path
        case BGIPathingAction.hydroCollect,
             BGIPathingAction.electroCollect,
             BGIPathingAction.anemoCollect,
             BGIPathingAction.pyroCollect:
            return .target
        case BGIPathingAction.stopFlying,
             BGIPathingAction.forceTp,
             BGIPathingAction.nahidaCollect,
             BGIPathingAction.pickAround,
             BGIPathingAction.upDownGrabLeaf,
             BGIPathingAction.combatScript,
             BGIPathingAction.mining,
             BGIPathingAction.linneaMining,
             BGIPathingAction.logOutput,
             BGIPathingAction.fishing,
             BGIPathingAction.exitAndRelogin,
             BGIPathingAction.wonderlandCycle,
             BGIPathingAction.setTime,
             BGIPathingAction.useGadget,
             BGIPathingAction.pickUpCollect:
            return .custom
        default:
            return nil
        }
    }

    private static func shouldRunAfterAction(_ waypoint: BGIPathingWaypointForTrack) -> Bool {
        guard let action = waypoint.action else { return false }
        switch action {
        case BGIPathingAction.nahidaCollect,
             BGIPathingAction.pickAround,
             BGIPathingAction.fight,
             BGIPathingAction.hydroCollect,
             BGIPathingAction.electroCollect,
             BGIPathingAction.anemoCollect,
             BGIPathingAction.pyroCollect,
             BGIPathingAction.combatScript,
             BGIPathingAction.mining,
             BGIPathingAction.linneaMining,
             BGIPathingAction.fishing,
             BGIPathingAction.exitAndRelogin,
             BGIPathingAction.wonderlandCycle,
             BGIPathingAction.setTime,
             BGIPathingAction.useGadget,
             BGIPathingAction.pickUpCollect:
            return true
        default:
            return false
        }
    }

    private func event(
        _ phase: BGIPathingNavigationPhase,
        segmentIndex: Int? = nil,
        waypointIndex: Int? = nil,
        waypoint: BGIPathingWaypointForTrack? = nil
    ) -> BGIPathingNavigationEvent {
        BGIPathingNavigationEvent(
            phase: phase,
            segmentIndex: segmentIndex,
            waypointIndex: waypointIndex,
            waypointType: waypoint?.type,
            action: waypoint?.action
        )
    }
}

enum BGIPathingExecutionStatus: String, Equatable, Sendable {
    case loadedAwaitingNavigationBackend
    case completedWithNavigationBackend
}

struct BGIPathingExecutionResult: Equatable, Sendable {
    var status: BGIPathingExecutionStatus
    var taskName: String
    var fileName: String
    var fullPath: String
    var waypointCount: Int
    var actionCounts: [String: Int]
    var autoPickEnabled: Bool
    var segmentCount: Int
    var successFight: Int
    var successEnd: Bool
}

enum BGIPathingTaskExecutorError: LocalizedError, Equatable {
    case invalidProjectPath(folderName: String, name: String)
    case missingTask(String)
    case unsupportedFutureBGIVersion(required: String, current: String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case let .invalidProjectPath(folderName, name):
            "Invalid BetterGI pathing project path: \(folderName)/\(name)"
        case let .missingTask(path):
            "BetterGI pathing task not found: \(path)"
        case let .unsupportedFutureBGIVersion(required, current):
            "BetterGI pathing task requires BGI \(required), current \(current)"
        case let .invalidJSON(message):
            "Invalid BetterGI pathing JSON: \(message)"
        }
    }
}

final class BGIPathingTaskExecutor {
    private let store: BGIRuntimeResourceStore
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let currentBGIVersion: String?

    init(
        store: BGIRuntimeResourceStore = .defaultStore(),
        fileManager: FileManager = .default,
        currentBGIVersion: String? = nil
    ) {
        self.store = store
        self.fileManager = fileManager
        self.currentBGIVersion = currentBGIVersion
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    func executeInstalledProject(name: String, folderName: String) throws -> BGIPathingExecutionResult {
        let task = try loadInstalledTask(name: name, folderName: folderName)
        return executionResult(for: task)
    }

    func executeInstalledProject(
        name: String,
        folderName: String,
        navigationBackend: BGIPathingNavigationBackend?
    ) async throws -> BGIPathingExecutionResult {
        let task = try loadInstalledTask(name: name, folderName: folderName)
        guard let navigationBackend else {
            return executionResult(for: task)
        }

        let pathingResult = try await BGIPathExecutor(backend: navigationBackend).pathing(task)
        return executionResult(for: task, pathingResult: pathingResult)
    }

    func loadInstalledTask(name: String, folderName: String) throws -> BGIPathingTask {
        let taskURL = try installedTaskURL(name: name, folderName: folderName)
        guard fileManager.fileExists(atPath: taskURL.path) else {
            throw BGIPathingTaskExecutorError.missingTask(taskURL.path)
        }
        return try loadTask(from: taskURL)
    }

    func loadTask(from url: URL) throws -> BGIPathingTask {
        let mergedData = try BGIPathingJSONMerger(fileManager: fileManager).mergedPathingData(pathingURL: url)
        var task: BGIPathingTask
        do {
            task = try decoder.decode(BGIPathingTask.self, from: mergedData)
        } catch {
            throw BGIPathingTaskExecutorError.invalidJSON(error.localizedDescription)
        }
        task.fileName = url.lastPathComponent
        task.fullPath = url.path
        for index in task.positions.indices {
            task.positions[index].pointExtParams.enableMonsterLootSplit = task.info.enableMonsterLootSplit
        }
        if let currentBGIVersion,
           let required = task.info.bgiVersion,
           Self.compareVersion(required, currentBGIVersion) == .orderedDescending {
            throw BGIPathingTaskExecutorError.unsupportedFutureBGIVersion(required: required, current: currentBGIVersion)
        }
        return task
    }

    private func installedTaskURL(name: String, folderName: String) throws -> URL {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty,
              !normalizedName.contains("/"),
              !normalizedName.contains("\\"),
              !normalizedName.contains("..")
        else {
            throw BGIPathingTaskExecutorError.invalidProjectPath(folderName: folderName, name: name)
        }

        if folderName.hasPrefix("/") {
            return URL(fileURLWithPath: folderName, isDirectory: true)
                .appendingPathComponent(normalizedName)
                .standardizedFileURL
        }

        let relativeFolder = folderName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativeFolder.contains("..") else {
            throw BGIPathingTaskExecutorError.invalidProjectPath(folderName: folderName, name: name)
        }
        let baseURL = store.userURL.appendingPathComponent("AutoPathing", isDirectory: true).standardizedFileURL
        let folderURL = relativeFolder.isEmpty
            ? baseURL
            : baseURL.appendingPathComponent(relativeFolder, isDirectory: true).standardizedFileURL
        let taskURL = folderURL.appendingPathComponent(normalizedName).standardizedFileURL
        guard taskURL.path == baseURL.path || taskURL.path.hasPrefix(baseURL.path + "/") else {
            throw BGIPathingTaskExecutorError.invalidProjectPath(folderName: folderName, name: name)
        }
        return taskURL
    }

    private func executionResult(for task: BGIPathingTask) -> BGIPathingExecutionResult {
        executionResult(for: task, pathingResult: nil)
    }

    private func executionResult(
        for task: BGIPathingTask,
        pathingResult: BGIPathExecutorResult?
    ) -> BGIPathingExecutionResult {
        let actionCounts = Dictionary(grouping: task.positions.compactMap(\.action), by: { $0 })
            .mapValues(\.count)
        return BGIPathingExecutionResult(
            status: pathingResult == nil ? .loadedAwaitingNavigationBackend : .completedWithNavigationBackend,
            taskName: task.info.name,
            fileName: task.fileName,
            fullPath: task.fullPath,
            waypointCount: task.positions.count,
            actionCounts: actionCounts,
            autoPickEnabled: task.config.realtimeTriggers["AutoPick"] ?? true,
            segmentCount: pathingResult?.segmentCount ?? BGIPathExecutor.convertWaypointsForTrack(task).count,
            successFight: pathingResult?.successFight ?? 0,
            successEnd: pathingResult?.successEnd ?? false
        )
    }

    private static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }
}

struct BGIPathingJSONMerger {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func mergedPathingData(pathingURL: URL) throws -> Data {
        let originalData = try Data(contentsOf: pathingURL)
        guard let directoryURL = pathingURL.deletingLastPathComponentIfNeeded,
              fileManager.fileExists(atPath: directoryURL.appendingPathComponent("control.json5").path)
        else {
            return originalData
        }

        guard let controlObject = try controlObject(from: directoryURL.appendingPathComponent("control.json5")) else {
            return originalData
        }

        var originalObject = try parseObject(originalData)
        merge(control: controlObject, target: &originalObject, fileBaseName: pathingURL.deletingPathExtension().lastPathComponent)
        return try JSONSerialization.data(withJSONObject: originalObject, options: [.sortedKeys])
    }

    private func controlObject(from url: URL, visited: Set<String> = []) throws -> [String: Any]? {
        let fileURL: URL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            fileURL = url
        } else {
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            fileURL = url.appendingPathComponent("control.json5")
        }

        let standardizedPath = fileURL.standardizedFileURL.path
        guard !visited.contains(standardizedPath) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let object = try parseObject(data)
        if let ref = object["ref"] as? String, !ref.isEmpty {
            let refURL = fileURL.deletingLastPathComponent().appendingPathComponent(ref)
            var nextVisited = visited
            nextVisited.insert(standardizedPath)
            return try controlObject(from: refURL, visited: nextVisited)
        }
        return object
    }

    private func merge(control: [String: Any], target: inout [String: Any], fileBaseName: String) {
        if let globalCover = control["global_cover"] as? [String: Any] {
            mergeObject(control: globalCover, target: &target)
        }

        guard let jsonList = control["json_list"] as? [[String: Any]] else { return }
        for item in jsonList where item["name"] as? String == fileBaseName {
            if let cover = item["cover"] as? [String: Any] {
                mergeObject(control: cover, target: &target)
            }
            break
        }
    }

    private func mergeObject(control: [String: Any], target: inout [String: Any]) {
        var skipKeys = Set<String>()

        if let objectCover = control["_obj_cover"] as? [String] {
            for property in objectCover {
                if let value = control[property] {
                    target[property] = value
                    skipKeys.insert(property)
                }
            }
            skipKeys.insert("_obj_cover")
        }

        if let arrayAdd = control["_arr_add"] as? [String] {
            for property in arrayAdd {
                guard let controlArray = control[property] as? [Any] else { continue }
                if let targetArray = target[property] as? [Any] {
                    target[property] = mergeArrays(source: controlArray, target: targetArray)
                } else {
                    target[property] = controlArray
                }
                skipKeys.insert(property)
            }
            skipKeys.insert("_arr_add")
        }

        for (key, value) in control where !skipKeys.contains(key) {
            if let nestedControl = value as? [String: Any] {
                if var nestedTarget = target[key] as? [String: Any] {
                    mergeObject(control: nestedControl, target: &nestedTarget)
                    target[key] = nestedTarget
                } else {
                    target[key] = nestedControl
                }
            } else {
                target[key] = value
            }
        }
    }

    private func mergeArrays(source: [Any], target: [Any]) -> [Any] {
        var result: [Any] = []
        var seen = Set<String>()
        for item in target + source {
            let key = compactJSONString(item)
            guard seen.insert(key).inserted else { continue }
            result.append(item)
        }
        return result
    }

    private func compactJSONString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value], options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return "\(value)"
        }
        return text
    }

    private func parseObject(_ data: Data) throws -> [String: Any] {
        let prepared = Self.prepareJSONText(String(data: data, encoding: .utf8) ?? "")
        let preparedData = Data(prepared.utf8)
        guard let object = try JSONSerialization.jsonObject(with: preparedData) as? [String: Any] else {
            throw BGIPathingTaskExecutorError.invalidJSON("expected object")
        }
        return object
    }

    private static func prepareJSONText(_ text: String) -> String {
        stripTrailingCommas(from: stripComments(from: text))
    }

    private static func stripComments(from text: String) -> String {
        var result = ""
        var index = text.startIndex
        var inString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if inString {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }

            if character == "\"" {
                inString = true
                result.append(character)
                index = next
                continue
            }

            if character == "/", next < text.endIndex {
                let nextCharacter = text[next]
                if nextCharacter == "/" {
                    index = text[next...].firstIndex(of: "\n") ?? text.endIndex
                    continue
                }
                if nextCharacter == "*" {
                    var blockIndex = text.index(after: next)
                    while blockIndex < text.endIndex {
                        let afterBlockIndex = text.index(after: blockIndex)
                        if text[blockIndex] == "*", afterBlockIndex < text.endIndex, text[afterBlockIndex] == "/" {
                            index = text.index(after: afterBlockIndex)
                            break
                        }
                        blockIndex = afterBlockIndex
                    }
                    if blockIndex >= text.endIndex {
                        index = text.endIndex
                    }
                    continue
                }
            }

            result.append(character)
            index = next
        }

        return result
    }

    private static func stripTrailingCommas(from text: String) -> String {
        var result = ""
        var index = text.startIndex
        var inString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            if inString {
                result.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if character == "\"" {
                inString = true
                result.append(character)
                index = text.index(after: index)
                continue
            }

            if character == "," {
                var lookahead = text.index(after: index)
                while lookahead < text.endIndex, text[lookahead].isWhitespace {
                    lookahead = text.index(after: lookahead)
                }
                if lookahead < text.endIndex, text[lookahead] == "}" || text[lookahead] == "]" {
                    index = text.index(after: index)
                    continue
                }
            }

            result.append(character)
            index = text.index(after: index)
        }
        return result
    }
}

private extension URL {
    var deletingLastPathComponentIfNeeded: URL? {
        guard !path.isEmpty else { return nil }
        return deletingLastPathComponent()
    }
}
