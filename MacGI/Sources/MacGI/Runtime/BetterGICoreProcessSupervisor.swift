import Darwin
import Foundation
import Security

struct BetterGICoreTriggerState: Sendable, Equatable {
    let name: String
    let displayName: String
    let enabled: Bool
    let canSetEnabled: Bool
    let priority: Int
    let exclusive: Bool
    let settingsAvailable: Bool
    let autoHangoutEventEnabled: Bool?
}

struct BetterGICoreAutoEatTriggerSettings: Sendable, Equatable {
    let checkInterval: Int
    let eatInterval: Int
}

struct BetterGICoreAutoPickTriggerSettings: Sendable, Equatable {
    let ocrEngine: String
    let ocrEngineOptions: [String]
    let fastModeEnabled: Bool
    let blackListEnabled: Bool
    let exactBlackList: String
    let fuzzyBlackList: String
    let whiteListEnabled: Bool
    let whiteList: String
    let pickKey: String
    let pickKeyOptions: [String]
}

struct BetterGICoreAutoSkipTriggerSettings: Sendable, Equatable {
    let quicklySkipConversationsEnabled: Bool
    let afterChooseOptionSleepDelay: Int
    let autoWaitDialogueOptionVoiceEnabled: Bool
    let dialogueOptionVoiceMaxWaitSeconds: Int
    let beforeClickConfirmDelay: Int
    let autoGetDailyRewardsEnabled: Bool
    let autoReExploreEnabled: Bool
    let clickChatOption: String
    let clickChatOptionOptions: [String]
    let customPriorityOptionsEnabled: Bool
    let customPriorityOptions: String
    let autoHangoutEventEnabled: Bool
    let autoHangoutEndChoose: String
    let autoHangoutEndChooseOptions: [String]
    let autoHangoutChooseOptionSleepDelay: Int
    let autoHangoutPressSkipEnabled: Bool
    let submitGoodsEnabled: Bool
    let closePopupPagedEnabled: Bool
}

struct BetterGICoreQuickTeleportTriggerSettings: Sendable, Equatable {
    let teleportListClickDelay: Int
    let waitTeleportPanelDelay: Int
    let hotkeyTpEnabled: Bool
}

struct BetterGICoreMapMaskTriggerSettings: Sendable, Equatable {
    let miniMapMaskEnabled: Bool
}

struct BetterGICoreSkillCdRule: Sendable, Equatable {
    var roleName: String
    var cdValueText: String
}

struct BetterGICoreSkillCdTriggerSettings: Sendable, Equatable {
    let customCdList: [BetterGICoreSkillCdRule]
    let triggerOnSkillUse: Bool
    let hideWhenZero: Bool
    let pX: Double
    let pY: Double
    let gap: Double
    let scale: Double
    let textNormalColor: String
    let backgroundNormalColor: String
    let textReadyColor: String
    let backgroundReadyColor: String
}

struct BetterGICoreMapMaskPickerSettings: Sendable, Equatable {
    let mapPointApiProvider: String
    let mapPointApiProviderOptions: [String]
    let hoYoLabLanguage: String
    let hoYoLabLanguageOptions: [String]
}

struct BetterGICoreMapMaskLabel: Sendable, Equatable, Identifiable {
    let id: String
    let parentID: String
    let name: String
    let iconURL: String
    let pointCount: Int
    let children: [BetterGICoreMapMaskLabel]
}

struct BetterGICoreSoloTask: Sendable, Equatable, Identifiable {
    let name: String
    let displayName: String
    let description: String
    let available: Bool
    let unavailableReason: String?
    let settingsAvailable: Bool
    let inputKind: String?
    let inputTitle: String?
    let inputPlaceholder: String?
    var id: String { name }
}

struct BetterGICoreAutoCookSettings: Sendable, Equatable {
    let checkIntervalMs: Int
    let stopTaskWhenRecoverButtonDetected: Bool
}

struct BetterGICoreAutoGeniusInvokationSettings: Sendable, Equatable {
    let strategyName: String
    let strategyOptions: [String]
    let sleepDelay: Int
}

struct BetterGICoreAutoFishingSettings: Sendable, Equatable {
    let autoThrowRodTimeOut: Int
    let wholeProcessTimeoutSeconds: Int
    let fishingTimePolicy: String
    let fishingTimePolicyOptions: [BetterGICoreNamedOption]
    let saveScreenshotOnKeyTick: Bool
}

struct BetterGICoreAutoWoodSettings: Sendable, Equatable {
    let roundNum: Int
    let dailyMaxCount: Int
    let useWonderlandRefresh: Bool
    let woodCountOcrEnabled: Bool
    let afterZSleepDelay: Int
}

struct BetterGICoreAutoMusicGameSettings: Sendable, Equatable {
    let mustCanorusLevel: Bool
    let musicLevel: String
    let musicLevelOptions: [String]
}

struct BetterGICoreAutoBossSettings: Sendable, Equatable {
    let bossName: String
    let bossOptions: [String]
    let strategyName: String
    let strategyOptions: [String]
    let teamName: String
    let specifyRunCount: Bool
    let runCount: Int
    let useTransientResin: Bool
    let useFragileResin: Bool
    let returnToStatueAfterEachRound: Bool
    let rewardRecognitionEnabled: Bool
    let reviveRetryCount: Int
}

struct BetterGICoreAutoLeyLineOutcropSettings: Sendable, Equatable {
    let leyLineOutcropType: String
    let leyLineOutcropTypeOptions: [String]
    let country: String
    let countryOptions: [String]
    let strategyName: String
    let strategyOptions: [String]
    let actionSchedulerByCd: String
    let seekEnemyEnabled: Bool
    let seekEnemyRotaryFactor: Int
    let seekEnemyIntervalSeconds: Int
    let kazuhaPickupEnabled: Bool
    let qinDoublePickUp: Bool
    let scanDropsAfterRewardEnabled: Bool
    let scanDropsAfterRewardSeconds: Int
    let isResinExhaustionMode: Bool
    let openModeCountMin: Bool
    let count: Int
    let useTransientResin: Bool
    let useFragileResin: Bool
    let team: String
    let friendshipTeam: String
    let timeout: Int
    let useAdventurerHandbook: Bool
    let isNotification: Bool
}

struct BetterGICoreAutoStygianOnslaughtSettings: Sendable, Equatable {
    let strategyName: String
    let strategyOptions: [String]
    let bossNum: Int
    let bossNumOptions: [Int]
    let fightTeamName: String
    let specifyResinUse: Bool
    let originalResinUseCount: Int
    let condensedResinUseCount: Int
    let transientResinUseCount: Int
    let fragileResinUseCount: Int
    let autoArtifactSalvage: Bool
    let maxArtifactStar: String
    let maxArtifactStarOptions: [String]
}

struct BetterGICoreAutoDomainSettings: Sendable, Equatable {
    let strategyName: String
    let strategyOptions: [String]
    let partyName: String
    let domainName: String
    let domainOptions: [String]
    let specifyResinUse: Bool
    let originalResinUseCount: Int
    let condensedResinUseCount: Int
    let transientResinUseCount: Int
    let fragileResinUseCount: Int
    let autoArtifactSalvage: Bool
    let maxArtifactStar: String
    let maxArtifactStarOptions: [String]
    let fightEndDelay: Double
    let shortMovement: Bool
    let walkToF: Bool
    let leftRightMoveTimes: Int
    let autoEat: Bool
    let rewardRecognitionEnabled: Bool
    let reviveRetryCount: Int
}

struct BetterGICoreNamedOption: Sendable, Equatable, Identifiable {
    let value: String
    let displayName: String
    var id: String { value }
}

struct BetterGICoreAutoArtifactSalvageSettings: Sendable, Equatable {
    let javaScript: String
    let artifactSetFilter: String
    let maxArtifactStar: String
    let maxArtifactStarOptions: [String]
    let maxNumToCheck: Int
    let recognitionFailurePolicy: String
    let recognitionFailurePolicyOptions: [BetterGICoreNamedOption]
}

struct BetterGICoreAutoFightSettings: Sendable, Equatable {
    let strategyName: String
    let strategyOptions: [String]
    let actionSchedulerByCd: String
    let fightFinishDetectEnabled: Bool
    let fastCheckEnabled: Bool
    let fastCheckParams: String
    let rotateFindEnemyEnabled: Bool
    let rotaryFactor: Int
    let checkBeforeBurst: Bool
    let isFirstCheck: Bool
    let checkEndDelay: String
    let beforeDetectDelay: String
    let guardianAvatar: String
    let guardianAvatarOptions: [String]
    let guardianCombatSkip: Bool
    let burstEnabled: Bool
    let guardianAvatarHold: Bool
    let pickDropsAfterFightEnabled: Bool
    let pickDropsAfterFightSeconds: Int
    let kazuhaPickupEnabled: Bool
    let qinDoublePickUp: Bool
    let expBasedPickupEnabled: Bool
    let timeout: Int
    let swimmingEnabled: Bool
}

struct BetterGICoreSoloTaskStatus: Sendable, Equatable {
    let taskID: String?
    let name: String?
    let state: String
    let error: String?
}

actor BetterGICoreProcessSupervisor {
    private static let startupPollLimit = 4_800
    enum StartupPhase: Sendable {
        case starting
        case waitingForSocket
        case provisioning
        case ready
        case failed(String)
    }

    enum State: Equatable, Sendable {
        case stopped
        case running(BetterGICoreHandshake)
        case failed(String)
    }

    private(set) var state: State = .stopped
    private let store: BGIRuntimeResourceStore
    private let executableURL: URL
    private var process: Process?
    private var client: BetterGICoreRPCClient?
    private var callbackClient: BetterGICorePlatformCallbackClient?
    private var callbackTask: Task<Void, Never>?
    private var platformHandler: BetterGICorePlatformCallbackClient.Handler?
    private var progressHandler: (@Sendable (StartupPhase) -> Void)?
    private var logHandler: (@Sendable (String) -> Void)?
    private var processGeneration = 0
    private var controlledRestartCount = 0
    private var intentionalStop = false
    private var outputPipe: Pipe?

    init(store: BGIRuntimeResourceStore = .defaultStore(), executableURL: URL? = nil) throws {
        self.store = store
        NSLog("BetterGI Core resolving executable URL")
        self.executableURL = try executableURL ?? Self.resolveExecutableURL()
        NSLog("BetterGI Core executable resolved: %@", self.executableURL.path)
    }

    func start(
        progressHandler: @escaping @Sendable (StartupPhase) -> Void,
        logHandler: @escaping @Sendable (String) -> Void,
        platformHandler: @escaping BetterGICorePlatformCallbackClient.Handler
    ) async throws -> BetterGICoreHandshake {
        if case .running(let handshake) = state { return handshake }
        progressHandler(.starting)
        self.platformHandler = platformHandler
        self.progressHandler = progressHandler
        self.logHandler = logHandler
        intentionalStop = false
        try store.createDirectorySkeleton()
        try store.synchronizeBundledGameTaskResources()
        let runURL = store.rootURL.appendingPathComponent("Run", isDirectory: true)
        try FileManager.default.createDirectory(at: runURL, withIntermediateDirectories: true)
        let socketURL = runURL.appendingPathComponent("core.sock")
        try? FileManager.default.removeItem(at: socketURL)
        let token = Self.makeSessionToken()
        let process = Process()
        processGeneration += 1
        let generation = processGeneration
        process.terminationHandler = { [weak self] _ in
            Task { await self?.processTerminated(generation: generation) }
        }
        process.executableURL = executableURL
        process.arguments = [
            "--runtime-root", store.rootURL.path,
            "--socket", socketURL.path,
            "--session-token", token,
            "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)
        ]
        let outputPipe = Pipe()
        let outputForwarder = CoreOutputForwarder(handler: logHandler)
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            outputForwarder.consume(handle.availableData)
        }
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        self.outputPipe = outputPipe
        do {
            try process.run()
            self.process = process
            let client = BetterGICoreRPCClient(socketPath: socketURL.path, sessionToken: token)
            self.client = client
            progressHandler(.waitingForSocket)
            try await waitForSocket(socketURL, process: process)
            let callbackClient = BetterGICorePlatformCallbackClient(
                socketPath: socketURL.path,
                sessionToken: token
            )
            self.callbackClient = callbackClient
            callbackTask = Task.detached { [weak self] in
                do {
                    try callbackClient.run(handler: platformHandler)
                } catch {
                    await self?.callbackFailed(error)
                }
            }
            try client.connect()
            let handshake = try client.handshake()
            progressHandler(.provisioning)
            var callbackAttached = false
            for _ in 0..<Self.startupPollLimit {
                let initialized = try client.initialize(
                    runtimeRoot: store.rootURL,
                    serverTimeZoneOffsetHours: 8,
                    jsNotificationEnabled: false,
                    mapMatchingMethod: "TemplateMatch"
                )
                if initialized["platformCallbackAttached"] as? Bool == true {
                    guard initialized["scriptHostServicesAttached"] as? Bool == true,
                          initialized["scriptServicePlatformAttached"] as? Bool == true,
                          initialized["platformAssetsInitialized"] as? Bool == true,
                          initialized["mapMatchingMethod"] as? String == "TemplateMatch"
                    else {
                        throw BetterGICoreRPCError.protocolViolation(
                            "Core did not attach the required script services."
                        )
                    }
                    callbackAttached = true
                    break
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            guard callbackAttached else {
                throw BetterGICoreRPCError.socket("Swift platform callback channel did not attach to Core.")
            }
            state = .running(handshake)
            progressHandler(.ready)
            return handshake
        } catch {
            intentionalStop = true
            _ = try? client?.request(method: "core.shutdown")
            client?.disconnect()
            callbackClient?.stop()
            callbackTask?.cancel()
            await Self.stopProcess(process)
            self.process = nil
            client = nil
            callbackClient = nil
            callbackTask = nil
            outputPipe.fileHandleForReading.readabilityHandler = nil
            self.outputPipe = nil
            state = .failed(error.localizedDescription)
            progressHandler(.failed(error.localizedDescription))
            intentionalStop = false
            throw error
        }
    }

    func listScriptGroups() throws -> [BetterGIScriptGroupSummary] {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try client.listScriptGroups()
    }

    func setScriptGroupProjectEnabled(groupName: String, projectIndex: Int, enabled: Bool) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(
            method: "catalog.setScriptGroupProjectEnabled",
            parameters: ["name": groupName, "projectIndex": projectIndex, "enabled": enabled]
        ) as? [String: Any], result["name"] as? String == groupName else {
            throw BetterGICoreRPCError.protocolViolation(
                "Invalid catalog.setScriptGroupProjectEnabled result."
            )
        }
    }

    private func runningClient() throws -> BetterGICoreRPCClient {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return client
    }

    func projectCommonSettings(groupName: String, projectIndex: Int) throws -> BetterGIProjectCommonSettings {
        try runningClient().projectCommonSettings(groupName: groupName, projectIndex: projectIndex)
    }

    func projectCustomSettings(groupName: String, projectIndex: Int) throws -> BetterGIProjectCustomSettings {
        try runningClient().projectCustomSettings(groupName: groupName, projectIndex: projectIndex)
    }

    func listAddCandidates(type: String) throws -> [BetterGIAddCandidate] {
        try runningClient().listAddCandidates(type: type)
    }

    func listPathingEntries() throws -> [BetterGIPathingEntry] {
        try runningClient().listPathingEntries()
    }

    func pathingDetail(id: String) throws -> BetterGIPathingDetail {
        try runningClient().pathingDetail(id: id)
    }

    func pathingSettings() throws -> BetterGIPathingSettings {
        try runningClient().pathingSettings()
    }

    func savePathingSettings(
        _ settings: BetterGIPathingSettings
    ) throws -> BetterGIPathingSettings {
        try runningClient().savePathingSettings(settings)
    }

    func pathingRootLocation() throws -> String {
        guard let result = try runningClient().request(
            method: "pathing.rootLocation") as? [String: Any],
              let path = result["path"] as? String
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid pathing root location.")
        }
        return path
    }

    func deletePathingEntry(id: String) throws {
        guard let result = try runningClient().request(
            method: "pathing.delete",
            parameters: ["id": id]) as? [String: Any],
              result["deleted"] as? Bool == true
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid pathing delete result.")
        }
    }

    func runPathingEntry(id: String) throws -> String {
        guard let result = try runningClient().request(
            method: "pathing.run",
            parameters: ["id": id]) as? [String: Any],
              let taskID = result["taskId"] as? String
        else {
            throw BetterGICoreRPCError.protocolViolation("Invalid pathing run result.")
        }
        return taskID
    }

    @discardableResult
    func catalogMutation(_ method: String, groupName: String, parameters: [String: Any] = [:]) throws -> [String: Any] {
        var payload = parameters
        payload["name"] = groupName
        guard let result = try runningClient().request(method: method, parameters: payload) as? [String: Any]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid \(method) result.") }
        return result
    }

    func saveProjectCommonSettings(groupName: String, settings: BetterGIProjectCommonSettings) throws {
        try catalogMutation("catalog.saveScriptGroupProjectCommonSettings", groupName: groupName, parameters: [
            "projectIndex": settings.projectIndex, "status": settings.status,
            "allowJsNotification": settings.allowJsNotification, "allowJsHttp": settings.allowJsHTTP
        ])
    }

    func saveProjectCustomSettings(groupName: String, settings: BetterGIProjectCustomSettings) throws {
        try catalogMutation("catalog.saveScriptGroupProjectCustomSettings", groupName: groupName, parameters: [
            "projectIndex": settings.projectIndex, "values": settings.values.mapValues(\.any)
        ])
    }

    func groupConfig(groupName: String) throws -> BetterGIGroupConfigSettings {
        guard let result = try runningClient().request(
            method: "catalog.getScriptGroupConfig", parameters: ["name": groupName]) as? [String: Any]
        else { throw BetterGICoreRPCError.protocolViolation("Invalid group config.") }
        let pathing = result["pathingConfig"] as? [String: Any] ?? [:]
        let taskCycle = pathing["taskCycleConfig"] as? [String: Any] ?? [:]
        let completion = pathing["taskCompletionSkipRuleConfig"] as? [String: Any] ?? [:]
        let priority = pathing["preExecutionPriorityConfig"] as? [String: Any] ?? [:]
        let shell = result["shellConfig"] as? [String: Any] ?? [:]
        let options = result["pathingOptions"] as? [String: Any] ?? [:]
        let decodeOptions: (String) throws -> [BetterGICoreNamedOption] = { key in
            guard let values = options[key] as? [[String: Any]] else {
                throw BetterGICoreRPCError.protocolViolation(
                    "Invalid group pathing option list \(key).")
            }
            return try values.map { value in
                guard let optionValue = value["value"] as? String,
                      let displayName = value["displayName"] as? String else {
                    throw BetterGICoreRPCError.protocolViolation(
                        "Invalid group pathing option in \(key).")
                }
                return BetterGICoreNamedOption(
                    value: optionValue, displayName: displayName)
            }
        }
        let recoverTiming = switch pathing["recoverTiming"] as? Int {
        case 1: "OnlyTeleport"
        case 2: "Never"
        default: "AnyWaypoint"
        }
        return BetterGIGroupConfigSettings(
            enabled: pathing["enabled"] as? Bool ?? true, autoPick: pathing["autoPickEnabled"] as? Bool ?? true,
            autoEat: pathing["autoEatEnabled"] as? Bool ?? false, autoSkip: pathing["autoSkipEnabled"] as? Bool ?? true,
            autoFight: pathing["autoFightEnabled"] as? Bool ?? true, autoRun: pathing["autoRunEnabled"] as? Bool ?? true,
            partyName: pathing["partyName"] as? String ?? "", visitStatue: pathing["isVisitStatueBeforeSwitchParty"] as? Bool ?? false,
            mainAvatar: pathing["mainAvatarIndex"] as? String ?? "", guardianAvatar: pathing["guardianAvatarIndex"] as? String ?? "",
            guardianInterval: pathing["guardianElementalSkillSecondInterval"] as? String ?? "",
            guardianLongPress: pathing["guardianElementalSkillLongPress"] as? Bool ?? false,
            gadgetInterval: pathing["useGadgetIntervalMs"] as? Int ?? 0,
            recoverTiming: recoverTiming,
            skipDuring: pathing["skipDuring"] as? String ?? "",
            hideOnRepeat: pathing["hideOnRepeat"] as? Bool ?? false,
            hurryOnAvatar: pathing["hurryOnAvatar"] as? String ?? "",
            travelMode: pathing["travelMode"] as? String ?? "精准靠近",
            distance: pathing["distance"] as? Int ?? 45,
            approachStopDistance: pathing["approachStopDistance"] as? Int ?? 25,
            switchToWalkEnabled: pathing["switchToWalkEnabled"] as? Bool ?? false,
            mwkJumpFlyEnabled: pathing["mwkJumpFlyEnabled"] as? Bool ?? true,
            mwkJumpFlyIntervalSeconds:
                (pathing["mwkJumpFlyIntervalSeconds"] as? NSNumber)?.doubleValue ?? 1,
            taskCycleEnabled: taskCycle["enable"] as? Bool ?? false,
            taskCycleBoundaryTime: taskCycle["boundaryTime"] as? Int ?? 0,
            taskCycleUsesServerTime:
                taskCycle["isBoundaryTimeBasedOnServerTime"] as? Bool ?? false,
            taskCycle: taskCycle["cycle"] as? Int ?? 1,
            taskCycleIndex: taskCycle["index"] as? Int ?? 1,
            completionSkipEnabled: completion["enable"] as? Bool ?? false,
            completionSkipPolicy:
                completion["skipPolicy"] as? String ?? "GroupPhysicalPathSkipPolicy",
            completionBoundaryTime: completion["boundaryTime"] as? Int ?? 4,
            completionUsesServerTime:
                completion["isBoundaryTimeBasedOnServerTime"] as? Bool ?? false,
            completionLastRunGapSeconds:
                completion["lastRunGapSeconds"] as? Int ?? -1,
            completionReferencePoint:
                completion["referencePoint"] as? String ?? "EndTime",
            priorityEnabled: priority["enabled"] as? Bool ?? false,
            priorityGroupNames: priority["groupNames"] as? String ?? "",
            priorityMaxRetryCount: priority["maxRetryCount"] as? Int ?? 1,
            avatarIndexOptions: options["avatarIndexes"] as? [String] ?? [],
            hurryOnAvatarOptions: options["hurryOnAvatars"] as? [String] ?? [],
            travelModeOptions: options["travelModes"] as? [String] ?? [],
            recoverTimingOptions: try decodeOptions("recoverTimings"),
            completionSkipPolicyOptions: try decodeOptions(
                "completionSkipPolicies"),
            completionReferencePointOptions: try decodeOptions(
                "completionReferencePoints"),
            enableShellConfig: result["enableShellConfig"] as? Bool ?? false, shellDisable: shell["disable"] as? Bool ?? false,
            shellTimeout: shell["timeout"] as? Int ?? 60, shellNoWindow: shell["noWindow"] as? Bool ?? true,
            shellOutput: shell["output"] as? Bool ?? true)
    }

    func saveGroupConfig(groupName: String, settings: BetterGIGroupConfigSettings) throws {
        try catalogMutation("catalog.saveScriptGroupConfig", groupName: groupName, parameters: ["config": [
            "pathingConfig": [
                "enabled": settings.enabled, "autoPickEnabled": settings.autoPick, "autoEatEnabled": settings.autoEat,
                "autoSkipEnabled": settings.autoSkip, "autoFightEnabled": settings.autoFight, "autoRunEnabled": settings.autoRun,
                "partyName": settings.partyName, "isVisitStatueBeforeSwitchParty": settings.visitStatue,
                "mainAvatarIndex": settings.mainAvatar, "guardianAvatarIndex": settings.guardianAvatar,
                "guardianElementalSkillSecondInterval": settings.guardianInterval,
                "guardianElementalSkillLongPress": settings.guardianLongPress,
                "useGadgetIntervalMs": settings.gadgetInterval,
                "recoverTiming": [
                    "AnyWaypoint": 0, "OnlyTeleport": 1, "Never": 2,
                ][settings.recoverTiming] ?? 0,
                "skipDuring": settings.skipDuring,
                "hideOnRepeat": settings.hideOnRepeat,
                "hurryOnAvatar": settings.hurryOnAvatar,
                "travelMode": settings.travelMode,
                "distance": settings.distance,
                "approachStopDistance": min(
                    settings.approachStopDistance, settings.distance),
                "switchToWalkEnabled": settings.switchToWalkEnabled,
                "mwkJumpFlyEnabled": settings.mwkJumpFlyEnabled,
                "mwkJumpFlyIntervalSeconds": settings.mwkJumpFlyIntervalSeconds,
                "taskCycleConfig": [
                    "enable": settings.taskCycleEnabled,
                    "boundaryTime": settings.taskCycleBoundaryTime,
                    "isBoundaryTimeBasedOnServerTime": settings.taskCycleUsesServerTime,
                    "cycle": settings.taskCycle,
                    "index": settings.taskCycleIndex,
                ],
                "taskCompletionSkipRuleConfig": [
                    "enable": settings.completionSkipEnabled,
                    "skipPolicy": settings.completionSkipPolicy,
                    "boundaryTime": settings.completionBoundaryTime,
                    "isBoundaryTimeBasedOnServerTime": settings.completionUsesServerTime,
                    "lastRunGapSeconds": settings.completionLastRunGapSeconds,
                    "referencePoint": settings.completionReferencePoint,
                ],
                "preExecutionPriorityConfig": [
                    "enabled": settings.priorityEnabled,
                    "groupNames": settings.priorityGroupNames,
                    "maxRetryCount": settings.priorityMaxRetryCount,
                ],
            ],
            "enableShellConfig": settings.enableShellConfig,
            "shellConfig": ["disable": settings.shellDisable, "timeout": settings.shellTimeout,
                            "noWindow": settings.shellNoWindow, "output": settings.shellOutput]
        ]])
    }

    func mutateSchedulerCatalog(groupName: String, mutation: BetterGISchedulerCatalogMutation) throws {
        switch mutation {
        case .add(let type, let ids, let command):
            try catalogMutation("catalog.addScriptGroupProjects", groupName: groupName, parameters: [
                "type": type, "candidateIds": ids, "shellCommand": command ?? NSNull()])
        case .remove(let index, let sameFolder):
            try catalogMutation("catalog.removeScriptGroupProject", groupName: groupName,
                                parameters: ["projectIndex": index, "sameFolder": sameFolder])
        case .clear: try catalogMutation("catalog.clearScriptGroup", groupName: groupName)
        case .reverse: try catalogMutation("catalog.reverseScriptGroup", groupName: groupName)
        case .updatePathingFolders: try catalogMutation("catalog.updateScriptGroupPathingFolders", groupName: groupName)
        case .setNext(let index):
            try catalogMutation("catalog.setScriptGroupNextProject", groupName: groupName, parameters: ["projectIndex": index])
        }
    }

    func projectLocation(groupName: String, projectIndex: Int) throws -> String {
        guard let result = try runningClient().request(
            method: "catalog.getScriptGroupProjectLocation",
            parameters: ["name": groupName, "projectIndex": projectIndex]) as? [String: Any],
              let path = result["path"] as? String
        else { throw BetterGICoreRPCError.protocolViolation("Invalid project location.") }
        return path
    }

    func exportMergedPathing(groupName: String) throws -> (path: String, count: Int) {
        guard let result = try runningClient().request(
            method: "catalog.exportMergedPathing", parameters: ["name": groupName]) as? [String: Any],
              let path = result["path"] as? String,
              let count = result["count"] as? Int
        else { throw BetterGICoreRPCError.protocolViolation("Invalid merged pathing export result.") }
        return (path, count)
    }

    func startRuntime() throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(method: "runtime.start") as? [String: Any],
              result["running"] as? Bool == true else {
            throw BetterGICoreRPCError.protocolViolation("Invalid runtime.start result.")
        }
    }

    func stopRuntime() throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(method: "runtime.stop") as? [String: Any],
              result["running"] as? Bool == false else {
            throw BetterGICoreRPCError.protocolViolation("Invalid runtime.stop result.")
        }
    }

    func refreshRuntimeGeometry() throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(method: "runtime.refreshGeometry") as? [String: Any],
              result["assetsReloaded"] as? Bool == true else {
            throw BetterGICoreRPCError.protocolViolation("Invalid runtime.refreshGeometry result.")
        }
    }

    func listScriptProjects() throws -> [BetterGIScriptProjectSummary] {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try client.listScriptProjects()
    }

    func scriptProjectRootLocation() throws -> String {
        try runningClient().scriptProjectRootLocation()
    }

    func scriptRepositoryState() throws -> BetterGIScriptRepositoryState {
        try runningClient().scriptRepositoryState()
    }

    func updateScriptRepository(channel: String, url: String) throws -> BetterGIScriptRepositoryUpdateResult {
        try runningClient().updateScriptRepository(channel: channel, url: url)
    }

    func resetScriptRepository() throws {
        try runningClient().resetScriptRepository()
    }

    func scriptRepositoryRepoJSON() throws -> String {
        try runningClient().scriptRepositoryWebString(method: "repository.web.getRepoJson")
    }

    func scriptRepositorySubscribedPathsJSON() throws -> String {
        try runningClient().scriptRepositoryWebString(method: "repository.web.getSubscribedScriptPaths")
    }

    func scriptRepositoryFile(path: String) throws -> String {
        try runningClient().scriptRepositoryWebString(
            method: "repository.web.getFile",
            parameters: ["path": path]
        )
    }

    func resetScriptRepositoryUpdateFlag(path: String) throws -> Bool {
        try runningClient().scriptRepositoryWebBool(
            method: "repository.web.updateSubscribed",
            parameters: ["path": path]
        )
    }

    func clearScriptRepositoryUpdateFlags() throws -> Bool {
        try runningClient().scriptRepositoryWebBool(method: "repository.web.clearUpdate")
    }

    func scriptRepositoryGuideStatus() throws -> Bool {
        try runningClient().scriptRepositoryWebBool(method: "repository.web.getGuideStatus")
    }

    func setScriptRepositoryGuideStatus(_ status: Bool) throws -> Bool {
        try runningClient().scriptRepositoryWebBool(
            method: "repository.web.setGuideStatus",
            parameters: ["status": status]
        )
    }

    func importScriptRepositoryURI(_ uri: String) throws -> Int {
        try runningClient().importScriptRepositoryURI(uri)
    }

    func runSchedulerGroup(name: String) throws -> String {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(
            method: "scheduler.run", parameters: ["groupName": name]
        ) as? [String: Any], let taskID = result["taskId"] as? String else {
            throw BetterGICoreRPCError.protocolViolation("Invalid scheduler.run result.")
        }
        return taskID
    }

    func runSchedulerGroups(names: [String]) throws -> String {
        guard !names.isEmpty else {
            throw BetterGICoreRPCError.protocolViolation(
                "scheduler.runGroups requires at least one group name.")
        }
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(
            method: "scheduler.runGroups", parameters: ["groupNames": names]
        ) as? [String: Any], let taskID = result["taskId"] as? String else {
            throw BetterGICoreRPCError.protocolViolation("Invalid scheduler.runGroups result.")
        }
        return taskID
    }

    func listTriggers() throws -> [BetterGICoreTriggerState] {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let items = try client.request(method: "trigger.list") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid trigger.list result.")
        }
        return try items.map { item in
            guard let name = item["name"] as? String,
                  let displayName = item["displayName"] as? String,
                  let enabled = item["enabled"] as? Bool,
                  let canSetEnabled = item["canSetEnabled"] as? Bool,
                  let priority = item["priority"] as? Int,
                  let exclusive = item["exclusive"] as? Bool,
                  let settingsAvailable = item["settingsAvailable"] as? Bool else {
                throw BetterGICoreRPCError.protocolViolation("Invalid trigger state.")
            }
            return BetterGICoreTriggerState(
                name: name, displayName: displayName, enabled: enabled,
                canSetEnabled: canSetEnabled,
                priority: priority, exclusive: exclusive,
                settingsAvailable: settingsAvailable,
                autoHangoutEventEnabled: item["autoHangoutEventEnabled"] as? Bool
            )
        }
    }

    func autoEatTriggerSettings() throws -> BetterGICoreAutoEatTriggerSettings {
        let value = try requestTriggerSettings(method: "trigger.settings.get", name: "AutoEat")
        guard let checkInterval = value["checkInterval"] as? Int,
              let eatInterval = value["eatInterval"] as? Int else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoEat trigger settings.")
        }
        return .init(checkInterval: checkInterval, eatInterval: eatInterval)
    }

    func autoPickTriggerSettings() throws -> BetterGICoreAutoPickTriggerSettings {
        try decodeAutoPickTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.get", name: "AutoPick"))
    }

    func autoSkipTriggerSettings() throws -> BetterGICoreAutoSkipTriggerSettings {
        try decodeAutoSkipTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.get", name: "AutoSkip"))
    }

    func saveAutoSkipTriggerSettings(_ settings: BetterGICoreAutoSkipTriggerSettings) throws
        -> BetterGICoreAutoSkipTriggerSettings {
        try decodeAutoSkipTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.save", name: "AutoSkip", settings: [
                "quicklySkipConversationsEnabled": settings.quicklySkipConversationsEnabled,
                "afterChooseOptionSleepDelay": settings.afterChooseOptionSleepDelay,
                "autoWaitDialogueOptionVoiceEnabled": settings.autoWaitDialogueOptionVoiceEnabled,
                "dialogueOptionVoiceMaxWaitSeconds": settings.dialogueOptionVoiceMaxWaitSeconds,
                "beforeClickConfirmDelay": settings.beforeClickConfirmDelay,
                "autoGetDailyRewardsEnabled": settings.autoGetDailyRewardsEnabled,
                "autoReExploreEnabled": settings.autoReExploreEnabled,
                "clickChatOption": settings.clickChatOption,
                "customPriorityOptionsEnabled": settings.customPriorityOptionsEnabled,
                "customPriorityOptions": settings.customPriorityOptions,
                "autoHangoutEventEnabled": settings.autoHangoutEventEnabled,
                "autoHangoutEndChoose": settings.autoHangoutEndChoose,
                "autoHangoutChooseOptionSleepDelay": settings.autoHangoutChooseOptionSleepDelay,
                "autoHangoutPressSkipEnabled": settings.autoHangoutPressSkipEnabled,
                "submitGoodsEnabled": settings.submitGoodsEnabled,
                "closePopupPagedEnabled": settings.closePopupPagedEnabled,
            ]))
    }

    func saveAutoPickTriggerSettings(_ settings: BetterGICoreAutoPickTriggerSettings) throws
        -> BetterGICoreAutoPickTriggerSettings {
        try decodeAutoPickTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.save", name: "AutoPick", settings: [
                "ocrEngine": settings.ocrEngine,
                "fastModeEnabled": settings.fastModeEnabled,
                "blackListEnabled": settings.blackListEnabled,
                "exactBlackList": settings.exactBlackList,
                "fuzzyBlackList": settings.fuzzyBlackList,
                "whiteListEnabled": settings.whiteListEnabled,
                "whiteList": settings.whiteList,
                "pickKey": settings.pickKey,
            ]))
    }

    func saveAutoEatTriggerSettings(_ settings: BetterGICoreAutoEatTriggerSettings) throws
        -> BetterGICoreAutoEatTriggerSettings {
        let value = try requestTriggerSettings(method: "trigger.settings.save", name: "AutoEat", settings: [
            "checkInterval": settings.checkInterval,
            "eatInterval": settings.eatInterval,
        ])
        guard let checkInterval = value["checkInterval"] as? Int,
              let eatInterval = value["eatInterval"] as? Int else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoEat trigger settings.")
        }
        return .init(checkInterval: checkInterval, eatInterval: eatInterval)
    }

    func quickTeleportTriggerSettings() throws -> BetterGICoreQuickTeleportTriggerSettings {
        try decodeQuickTeleportTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.get", name: "QuickTeleport"))
    }

    func saveQuickTeleportTriggerSettings(_ settings: BetterGICoreQuickTeleportTriggerSettings) throws
        -> BetterGICoreQuickTeleportTriggerSettings {
        try decodeQuickTeleportTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.save", name: "QuickTeleport", settings: [
                "teleportListClickDelay": settings.teleportListClickDelay,
                "waitTeleportPanelDelay": settings.waitTeleportPanelDelay,
                "hotkeyTpEnabled": settings.hotkeyTpEnabled,
            ]))
    }

    func mapMaskTriggerSettings() throws -> BetterGICoreMapMaskTriggerSettings {
        try decodeMapMaskTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.get", name: "MapMask"))
    }

    func skillCdTriggerSettings() throws -> BetterGICoreSkillCdTriggerSettings {
        try decodeSkillCdTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.get", name: "SkillCd"))
    }

    func saveSkillCdTriggerSettings(_ settings: BetterGICoreSkillCdTriggerSettings) throws
        -> BetterGICoreSkillCdTriggerSettings {
        try decodeSkillCdTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.save", name: "SkillCd", settings: [
                "customCdList": settings.customCdList.map {
                    ["roleName": $0.roleName, "cdValueText": $0.cdValueText]
                },
                "triggerOnSkillUse": settings.triggerOnSkillUse,
                "hideWhenZero": settings.hideWhenZero,
                "pX": settings.pX,
                "pY": settings.pY,
                "gap": settings.gap,
                "scale": settings.scale,
                "textNormalColor": settings.textNormalColor,
                "backgroundNormalColor": settings.backgroundNormalColor,
                "textReadyColor": settings.textReadyColor,
                "backgroundReadyColor": settings.backgroundReadyColor,
            ]))
    }

    func saveMapMaskTriggerSettings(_ settings: BetterGICoreMapMaskTriggerSettings) throws
        -> BetterGICoreMapMaskTriggerSettings {
        try decodeMapMaskTriggerSettings(requestTriggerSettings(
            method: "trigger.settings.save", name: "MapMask", settings: [
                "miniMapMaskEnabled": settings.miniMapMaskEnabled,
            ]))
    }

    func mapMaskPickerSettings() throws -> BetterGICoreMapMaskPickerSettings {
        guard case .running = state, let client,
              let value = try client.request(method: "mapMask.settings.get") as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask picker settings result.")
        }
        return try decodeMapMaskPickerSettings(value)
    }

    func saveMapMaskPickerSettings(_ settings: BetterGICoreMapMaskPickerSettings) throws
        -> BetterGICoreMapMaskPickerSettings {
        guard case .running = state, let client,
              let value = try client.request(method: "mapMask.settings.save", parameters: ["settings": [
                "mapPointApiProvider": settings.mapPointApiProvider,
                "hoYoLabLanguage": settings.hoYoLabLanguage,
              ]]) as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask picker settings result.")
        }
        return try decodeMapMaskPickerSettings(value)
    }

    func mapMaskPointCatalog() throws -> [BetterGICoreMapMaskLabel] {
        guard case .running = state, let client,
              let values = try client.request(method: "mapMask.catalog") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask catalog result.")
        }
        return try values.map(decodeMapMaskLabel)
    }

    func mapMaskPointSelection() throws -> Set<String> {
        guard case .running = state, let client,
              let value = try client.request(method: "mapMask.selection.get") as? [String: Any],
              let selectedIDs = value["selectedIds"] as? [String] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask selection result.")
        }
        return Set(selectedIDs)
    }

    func saveMapMaskPointSelection(_ selectedIDs: Set<String>) throws -> Set<String> {
        guard case .running = state, let client,
              let value = try client.request(
                method: "mapMask.selection.save",
                parameters: ["selectedIds": selectedIDs.sorted()]) as? [String: Any],
              let savedIDs = value["selectedIds"] as? [String] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask selection result.")
        }
        return Set(savedIDs)
    }

    private func requestTriggerSettings(
        method: String, name: String, settings: [String: Any]? = nil
    ) throws -> [String: Any] {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        var parameters: [String: Any] = ["name": name]
        if let settings { parameters["settings"] = settings }
        guard let value = try client.request(method: method, parameters: parameters) as? [String: Any] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid trigger settings result.")
        }
        return value
    }

    private func decodeQuickTeleportTriggerSettings(_ value: [String: Any]) throws
        -> BetterGICoreQuickTeleportTriggerSettings {
        guard let listDelay = value["teleportListClickDelay"] as? Int,
              let panelDelay = value["waitTeleportPanelDelay"] as? Int,
              let hotkeyEnabled = value["hotkeyTpEnabled"] as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid QuickTeleport trigger settings.")
        }
        return .init(teleportListClickDelay: listDelay,
                     waitTeleportPanelDelay: panelDelay,
                     hotkeyTpEnabled: hotkeyEnabled)
    }

    private func decodeAutoPickTriggerSettings(_ value: [String: Any]) throws
        -> BetterGICoreAutoPickTriggerSettings {
        guard let ocrEngine = value["ocrEngine"] as? String,
              let ocrEngineOptions = value["ocrEngineOptions"] as? [String],
              let fastModeEnabled = value["fastModeEnabled"] as? Bool,
              let blackListEnabled = value["blackListEnabled"] as? Bool,
              let exactBlackList = value["exactBlackList"] as? String,
              let fuzzyBlackList = value["fuzzyBlackList"] as? String,
              let whiteListEnabled = value["whiteListEnabled"] as? Bool,
              let whiteList = value["whiteList"] as? String,
              let pickKey = value["pickKey"] as? String,
              let pickKeyOptions = value["pickKeyOptions"] as? [String] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoPick trigger settings.")
        }
        return .init(
            ocrEngine: ocrEngine, ocrEngineOptions: ocrEngineOptions,
            fastModeEnabled: fastModeEnabled,
            blackListEnabled: blackListEnabled, exactBlackList: exactBlackList,
            fuzzyBlackList: fuzzyBlackList, whiteListEnabled: whiteListEnabled,
            whiteList: whiteList, pickKey: pickKey, pickKeyOptions: pickKeyOptions)
    }

    private func decodeAutoSkipTriggerSettings(_ value: [String: Any]) throws
        -> BetterGICoreAutoSkipTriggerSettings {
        guard let quicklySkipConversationsEnabled = value["quicklySkipConversationsEnabled"] as? Bool,
              let afterChooseOptionSleepDelay = value["afterChooseOptionSleepDelay"] as? Int,
              let autoWaitDialogueOptionVoiceEnabled = value["autoWaitDialogueOptionVoiceEnabled"] as? Bool,
              let dialogueOptionVoiceMaxWaitSeconds = value["dialogueOptionVoiceMaxWaitSeconds"] as? Int,
              let beforeClickConfirmDelay = value["beforeClickConfirmDelay"] as? Int,
              let autoGetDailyRewardsEnabled = value["autoGetDailyRewardsEnabled"] as? Bool,
              let autoReExploreEnabled = value["autoReExploreEnabled"] as? Bool,
              let clickChatOption = value["clickChatOption"] as? String,
              let clickChatOptionOptions = value["clickChatOptionOptions"] as? [String],
              let customPriorityOptionsEnabled = value["customPriorityOptionsEnabled"] as? Bool,
              let customPriorityOptions = value["customPriorityOptions"] as? String,
              let autoHangoutEventEnabled = value["autoHangoutEventEnabled"] as? Bool,
              let autoHangoutEndChoose = value["autoHangoutEndChoose"] as? String,
              let autoHangoutEndChooseOptions = value["autoHangoutEndChooseOptions"] as? [String],
              let autoHangoutChooseOptionSleepDelay = value["autoHangoutChooseOptionSleepDelay"] as? Int,
              let autoHangoutPressSkipEnabled = value["autoHangoutPressSkipEnabled"] as? Bool,
              let submitGoodsEnabled = value["submitGoodsEnabled"] as? Bool,
              let closePopupPagedEnabled = value["closePopupPagedEnabled"] as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoSkip trigger settings.")
        }
        return .init(
            quicklySkipConversationsEnabled: quicklySkipConversationsEnabled,
            afterChooseOptionSleepDelay: afterChooseOptionSleepDelay,
            autoWaitDialogueOptionVoiceEnabled: autoWaitDialogueOptionVoiceEnabled,
            dialogueOptionVoiceMaxWaitSeconds: dialogueOptionVoiceMaxWaitSeconds,
            beforeClickConfirmDelay: beforeClickConfirmDelay,
            autoGetDailyRewardsEnabled: autoGetDailyRewardsEnabled,
            autoReExploreEnabled: autoReExploreEnabled,
            clickChatOption: clickChatOption,
            clickChatOptionOptions: clickChatOptionOptions,
            customPriorityOptionsEnabled: customPriorityOptionsEnabled,
            customPriorityOptions: customPriorityOptions,
            autoHangoutEventEnabled: autoHangoutEventEnabled,
            autoHangoutEndChoose: autoHangoutEndChoose,
            autoHangoutEndChooseOptions: autoHangoutEndChooseOptions,
            autoHangoutChooseOptionSleepDelay: autoHangoutChooseOptionSleepDelay,
            autoHangoutPressSkipEnabled: autoHangoutPressSkipEnabled,
            submitGoodsEnabled: submitGoodsEnabled,
            closePopupPagedEnabled: closePopupPagedEnabled)
    }

    private func decodeMapMaskTriggerSettings(_ value: [String: Any]) throws
        -> BetterGICoreMapMaskTriggerSettings {
        guard let enabled = value["miniMapMaskEnabled"] as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask trigger settings.")
        }
        return .init(miniMapMaskEnabled: enabled)
    }

    private func decodeSkillCdTriggerSettings(_ value: [String: Any]) throws
        -> BetterGICoreSkillCdTriggerSettings {
        guard let rawRules = value["customCdList"] as? [[String: Any]],
              let triggerOnSkillUse = value["triggerOnSkillUse"] as? Bool,
              let hideWhenZero = value["hideWhenZero"] as? Bool,
              let pX = value["pX"] as? Double,
              let pY = value["pY"] as? Double,
              let gap = value["gap"] as? Double,
              let scale = value["scale"] as? Double,
              let textNormalColor = value["textNormalColor"] as? String,
              let backgroundNormalColor = value["backgroundNormalColor"] as? String,
              let textReadyColor = value["textReadyColor"] as? String,
              let backgroundReadyColor = value["backgroundReadyColor"] as? String else {
            throw BetterGICoreRPCError.protocolViolation("Invalid SkillCd trigger settings.")
        }
        let rules = try rawRules.map { rule in
            guard let roleName = rule["roleName"] as? String,
                  let cdValueText = rule["cdValueText"] as? String else {
                throw BetterGICoreRPCError.protocolViolation("Invalid SkillCd role rule.")
            }
            return BetterGICoreSkillCdRule(roleName: roleName, cdValueText: cdValueText)
        }
        return .init(
            customCdList: rules,
            triggerOnSkillUse: triggerOnSkillUse,
            hideWhenZero: hideWhenZero,
            pX: pX,
            pY: pY,
            gap: gap,
            scale: scale,
            textNormalColor: textNormalColor,
            backgroundNormalColor: backgroundNormalColor,
            textReadyColor: textReadyColor,
            backgroundReadyColor: backgroundReadyColor)
    }

    private func decodeMapMaskPickerSettings(_ value: [String: Any]) throws
        -> BetterGICoreMapMaskPickerSettings {
        guard let provider = value["mapPointApiProvider"] as? String,
              let providerOptions = value["mapPointApiProviderOptions"] as? [String],
              let language = value["hoYoLabLanguage"] as? String,
              let languageOptions = value["hoYoLabLanguageOptions"] as? [String] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask picker settings.")
        }
        return .init(
            mapPointApiProvider: provider,
            mapPointApiProviderOptions: providerOptions,
            hoYoLabLanguage: language,
            hoYoLabLanguageOptions: languageOptions)
    }

    private func decodeMapMaskLabel(_ value: [String: Any]) throws -> BetterGICoreMapMaskLabel {
        guard let id = value["id"] as? String,
              let parentID = value["parentId"] as? String,
              let name = value["name"] as? String,
              let iconURL = value["iconUrl"] as? String,
              let pointCount = value["pointCount"] as? Int,
              let childValues = value["children"] as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid MapMask label result.")
        }
        return .init(
            id: id, parentID: parentID, name: name, iconURL: iconURL,
            pointCount: pointCount, children: try childValues.map(decodeMapMaskLabel))
    }

    func setTriggerEnabled(name: String, enabled: Bool) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let result = try client.request(
            method: "trigger.setEnabled", parameters: ["name": name, "enabled": enabled]
        ) as? [String: Any], result["name"] as? String == name,
              result["enabled"] as? Bool == enabled else {
            throw BetterGICoreRPCError.protocolViolation("Invalid trigger.setEnabled result.")
        }
    }

    func listSoloTasks() throws -> [BetterGICoreSoloTask] {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        guard let items = try client.request(method: "solo.list") as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid solo.list result.")
        }
        return try items.map { item in
            guard let name = item["name"] as? String,
                  let displayName = item["displayName"] as? String,
                  let description = item["description"] as? String,
                  let available = item["available"] as? Bool else {
                throw BetterGICoreRPCError.protocolViolation("Invalid solo task descriptor.")
            }
            return BetterGICoreSoloTask(
                name: name, displayName: displayName, description: description,
                available: available,
                unavailableReason: item["unavailableReason"] as? String,
                settingsAvailable: item["settingsAvailable"] as? Bool ?? false,
                inputKind: item["inputKind"] as? String,
                inputTitle: item["inputTitle"] as? String,
                inputPlaceholder: item["inputPlaceholder"] as? String
            )
        }
    }

    func autoCookSettings() throws -> BetterGICoreAutoCookSettings {
        try decodeAutoCookSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoCook"]
        ))
    }

    func autoGeniusInvokationSettings() throws
        -> BetterGICoreAutoGeniusInvokationSettings {
        try decodeAutoGeniusInvokationSettings(requestSoloSettings(
            method: "solo.settings.get",
            parameters: ["name": "AutoGeniusInvokation"]
        ))
    }

    func saveAutoGeniusInvokationSettings(
        _ settings: BetterGICoreAutoGeniusInvokationSettings
    ) throws -> BetterGICoreAutoGeniusInvokationSettings {
        try decodeAutoGeniusInvokationSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoGeniusInvokation", "settings": [
                "strategyName": settings.strategyName,
                "sleepDelay": settings.sleepDelay,
            ]]
        ))
    }

    func autoFishingSettings() throws -> BetterGICoreAutoFishingSettings {
        try decodeAutoFishingSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoFishing"]
        ))
    }

    func saveAutoFishingSettings(_ settings: BetterGICoreAutoFishingSettings) throws
        -> BetterGICoreAutoFishingSettings {
        try decodeAutoFishingSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoFishing", "settings": [
                "autoThrowRodTimeOut": settings.autoThrowRodTimeOut,
                "wholeProcessTimeoutSeconds": settings.wholeProcessTimeoutSeconds,
                "fishingTimePolicy": settings.fishingTimePolicy,
                "saveScreenshotOnKeyTick": settings.saveScreenshotOnKeyTick,
            ]]
        ))
    }

    func saveAutoCookSettings(_ settings: BetterGICoreAutoCookSettings) throws
        -> BetterGICoreAutoCookSettings {
        try decodeAutoCookSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: [
                "name": "AutoCook",
                "settings": [
                    "checkIntervalMs": settings.checkIntervalMs,
                    "stopTaskWhenRecoverButtonDetected": settings.stopTaskWhenRecoverButtonDetected,
                ],
            ]
        ))
    }

    func autoWoodSettings() throws -> BetterGICoreAutoWoodSettings {
        try decodeAutoWoodSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoWood"]
        ))
    }

    func saveAutoWoodSettings(_ settings: BetterGICoreAutoWoodSettings) throws
        -> BetterGICoreAutoWoodSettings {
        try decodeAutoWoodSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoWood", "settings": [
                "roundNum": settings.roundNum,
                "dailyMaxCount": settings.dailyMaxCount,
                "useWonderlandRefresh": settings.useWonderlandRefresh,
                "woodCountOcrEnabled": settings.woodCountOcrEnabled,
                "afterZSleepDelay": settings.afterZSleepDelay,
            ]]
        ))
    }

    func autoMusicGameSettings() throws -> BetterGICoreAutoMusicGameSettings {
        try decodeAutoMusicGameSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoMusicGame"]
        ))
    }

    func saveAutoMusicGameSettings(_ settings: BetterGICoreAutoMusicGameSettings) throws
        -> BetterGICoreAutoMusicGameSettings {
        try decodeAutoMusicGameSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoMusicGame", "settings": [
                "mustCanorusLevel": settings.mustCanorusLevel,
                "musicLevel": settings.musicLevel,
            ]]
        ))
    }

    func autoBossSettings() throws -> BetterGICoreAutoBossSettings {
        try decodeAutoBossSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoBoss"]
        ))
    }

    func saveAutoBossSettings(_ settings: BetterGICoreAutoBossSettings) throws
        -> BetterGICoreAutoBossSettings {
        try decodeAutoBossSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoBoss", "settings": [
                "bossName": settings.bossName,
                "strategyName": settings.strategyName,
                "teamName": settings.teamName,
                "specifyRunCount": settings.specifyRunCount,
                "runCount": settings.runCount,
                "useTransientResin": settings.useTransientResin,
                "useFragileResin": settings.useFragileResin,
                "returnToStatueAfterEachRound": settings.returnToStatueAfterEachRound,
                "rewardRecognitionEnabled": settings.rewardRecognitionEnabled,
                "reviveRetryCount": settings.reviveRetryCount,
            ]]
        ))
    }

    func autoDomainSettings() throws -> BetterGICoreAutoDomainSettings {
        try decodeAutoDomainSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoDomain"]
        ))
    }

    func autoStygianOnslaughtSettings() throws -> BetterGICoreAutoStygianOnslaughtSettings {
        try decodeAutoStygianOnslaughtSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoStygianOnslaught"]
        ))
    }

    func saveAutoStygianOnslaughtSettings(
        _ settings: BetterGICoreAutoStygianOnslaughtSettings
    ) throws -> BetterGICoreAutoStygianOnslaughtSettings {
        try decodeAutoStygianOnslaughtSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoStygianOnslaught", "settings": [
                "strategyName": settings.strategyName,
                "bossNum": settings.bossNum,
                "fightTeamName": settings.fightTeamName,
                "specifyResinUse": settings.specifyResinUse,
                "originalResinUseCount": settings.originalResinUseCount,
                "condensedResinUseCount": settings.condensedResinUseCount,
                "transientResinUseCount": settings.transientResinUseCount,
                "fragileResinUseCount": settings.fragileResinUseCount,
                "autoArtifactSalvage": settings.autoArtifactSalvage,
                "maxArtifactStar": settings.maxArtifactStar,
            ]]
        ))
    }

    func autoLeyLineOutcropSettings() throws -> BetterGICoreAutoLeyLineOutcropSettings {
        try decodeAutoLeyLineOutcropSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoLeyLineOutcrop"]
        ))
    }

    func saveAutoLeyLineOutcropSettings(_ settings: BetterGICoreAutoLeyLineOutcropSettings) throws
        -> BetterGICoreAutoLeyLineOutcropSettings {
        try decodeAutoLeyLineOutcropSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoLeyLineOutcrop", "settings": [
                "leyLineOutcropType": settings.leyLineOutcropType,
                "country": settings.country,
                "strategyName": settings.strategyName,
                "actionSchedulerByCd": settings.actionSchedulerByCd,
                "seekEnemyEnabled": settings.seekEnemyEnabled,
                "seekEnemyRotaryFactor": settings.seekEnemyRotaryFactor,
                "seekEnemyIntervalSeconds": settings.seekEnemyIntervalSeconds,
                "kazuhaPickupEnabled": settings.kazuhaPickupEnabled,
                "qinDoublePickUp": settings.qinDoublePickUp,
                "scanDropsAfterRewardEnabled": settings.scanDropsAfterRewardEnabled,
                "scanDropsAfterRewardSeconds": settings.scanDropsAfterRewardSeconds,
                "isResinExhaustionMode": settings.isResinExhaustionMode,
                "openModeCountMin": settings.openModeCountMin,
                "count": settings.count,
                "useTransientResin": settings.useTransientResin,
                "useFragileResin": settings.useFragileResin,
                "team": settings.team,
                "friendshipTeam": settings.friendshipTeam,
                "timeout": settings.timeout,
                "useAdventurerHandbook": settings.useAdventurerHandbook,
                "isNotification": settings.isNotification,
            ]]
        ))
    }

    func saveAutoDomainSettings(_ settings: BetterGICoreAutoDomainSettings) throws
        -> BetterGICoreAutoDomainSettings {
        try decodeAutoDomainSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoDomain", "settings": [
                "strategyName": settings.strategyName,
                "partyName": settings.partyName,
                "domainName": settings.domainName,
                "specifyResinUse": settings.specifyResinUse,
                "originalResinUseCount": settings.originalResinUseCount,
                "condensedResinUseCount": settings.condensedResinUseCount,
                "transientResinUseCount": settings.transientResinUseCount,
                "fragileResinUseCount": settings.fragileResinUseCount,
                "autoArtifactSalvage": settings.autoArtifactSalvage,
                "maxArtifactStar": settings.maxArtifactStar,
                "fightEndDelay": settings.fightEndDelay,
                "shortMovement": settings.shortMovement,
                "walkToF": settings.walkToF,
                "leftRightMoveTimes": settings.leftRightMoveTimes,
                "autoEat": settings.autoEat,
                "rewardRecognitionEnabled": settings.rewardRecognitionEnabled,
                "reviveRetryCount": settings.reviveRetryCount,
            ]]
        ))
    }

    func autoArtifactSalvageSettings() throws -> BetterGICoreAutoArtifactSalvageSettings {
        try decodeAutoArtifactSalvageSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoArtifactSalvage"]
        ))
    }

    func autoFightSettings() throws -> BetterGICoreAutoFightSettings {
        try decodeAutoFightSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoFight"]
        ))
    }

    func saveAutoFightSettings(_ settings: BetterGICoreAutoFightSettings) throws
        -> BetterGICoreAutoFightSettings {
        try decodeAutoFightSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoFight", "settings": [
                "strategyName": settings.strategyName,
                "actionSchedulerByCd": settings.actionSchedulerByCd,
                "fightFinishDetectEnabled": settings.fightFinishDetectEnabled,
                "fastCheckEnabled": settings.fastCheckEnabled,
                "fastCheckParams": settings.fastCheckParams,
                "rotateFindEnemyEnabled": settings.rotateFindEnemyEnabled,
                "rotaryFactor": settings.rotaryFactor,
                "checkBeforeBurst": settings.checkBeforeBurst,
                "isFirstCheck": settings.isFirstCheck,
                "checkEndDelay": settings.checkEndDelay,
                "beforeDetectDelay": settings.beforeDetectDelay,
                "guardianAvatar": settings.guardianAvatar,
                "guardianCombatSkip": settings.guardianCombatSkip,
                "burstEnabled": settings.burstEnabled,
                "guardianAvatarHold": settings.guardianAvatarHold,
                "pickDropsAfterFightEnabled": settings.pickDropsAfterFightEnabled,
                "pickDropsAfterFightSeconds": settings.pickDropsAfterFightSeconds,
                "kazuhaPickupEnabled": settings.kazuhaPickupEnabled,
                "qinDoublePickUp": settings.qinDoublePickUp,
                "expBasedPickupEnabled": settings.expBasedPickupEnabled,
                "timeout": settings.timeout,
                "swimmingEnabled": settings.swimmingEnabled,
            ]]
        ))
    }

    func saveAutoArtifactSalvageSettings(_ settings: BetterGICoreAutoArtifactSalvageSettings) throws
        -> BetterGICoreAutoArtifactSalvageSettings {
        try decodeAutoArtifactSalvageSettings(requestSoloSettings(
            method: "solo.settings.save",
            parameters: ["name": "AutoArtifactSalvage", "settings": [
                "javaScript": settings.javaScript,
                "artifactSetFilter": settings.artifactSetFilter,
                "maxArtifactStar": settings.maxArtifactStar,
                "maxNumToCheck": settings.maxNumToCheck,
                "recognitionFailurePolicy": settings.recognitionFailurePolicy,
            ]]
        ))
    }

    private func requestSoloSettings(method: String, parameters: [String: Any]) throws -> Any {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try client.request(method: method, parameters: parameters)
    }

    private func decodeAutoGeniusInvokationSettings(_ value: Any) throws
        -> BetterGICoreAutoGeniusInvokationSettings {
        guard let value = value as? [String: Any],
              value["name"] as? String == "AutoGeniusInvokation",
              let strategyName = value["strategyName"] as? String,
              let strategyOptions = value["strategyOptions"] as? [String],
              let sleepDelay = value["sleepDelay"] as? Int else {
            throw BetterGICoreRPCError.protocolViolation(
                "Invalid AutoGeniusInvokation settings.")
        }
        return .init(
            strategyName: strategyName,
            strategyOptions: strategyOptions,
            sleepDelay: sleepDelay)
    }

    private func decodeAutoCookSettings(_ value: Any) throws -> BetterGICoreAutoCookSettings {
        guard let result = value as? [String: Any],
              result["name"] as? String == "AutoCook",
              let interval = result["checkIntervalMs"] as? Int,
              let stopWhenDetected = result["stopTaskWhenRecoverButtonDetected"] as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoCook settings.")
        }
        return BetterGICoreAutoCookSettings(
            checkIntervalMs: interval,
            stopTaskWhenRecoverButtonDetected: stopWhenDetected
        )
    }

    private func decodeAutoFishingSettings(_ value: Any) throws
        -> BetterGICoreAutoFishingSettings {
        guard let value = value as? [String: Any],
              value["name"] as? String == "AutoFishing",
              let autoThrowRodTimeOut = value["autoThrowRodTimeOut"] as? Int,
              let wholeProcessTimeoutSeconds = value["wholeProcessTimeoutSeconds"] as? Int,
              let fishingTimePolicy = value["fishingTimePolicy"] as? String,
              let rawOptions = value["fishingTimePolicyOptions"] as? [[String: Any]],
              let saveScreenshotOnKeyTick = value["saveScreenshotOnKeyTick"] as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoFishing settings.")
        }
        let options = try rawOptions.map { option -> BetterGICoreNamedOption in
            guard let optionValue = option["value"] as? String,
                  let displayName = option["displayName"] as? String else {
                throw BetterGICoreRPCError.protocolViolation(
                    "Invalid AutoFishing time policy option.")
            }
            return .init(value: optionValue, displayName: displayName)
        }
        return .init(autoThrowRodTimeOut: autoThrowRodTimeOut,
                     wholeProcessTimeoutSeconds: wholeProcessTimeoutSeconds,
                     fishingTimePolicy: fishingTimePolicy,
                     fishingTimePolicyOptions: options,
                     saveScreenshotOnKeyTick: saveScreenshotOnKeyTick)
    }

    private func decodeAutoWoodSettings(_ value: Any) throws -> BetterGICoreAutoWoodSettings {
        guard let value = value as? [String: Any], value["name"] as? String == "AutoWood",
              let roundNum = value["roundNum"] as? Int,
              let dailyMaxCount = value["dailyMaxCount"] as? Int,
              let useWonderlandRefresh = value["useWonderlandRefresh"] as? Bool,
              let woodCountOcrEnabled = value["woodCountOcrEnabled"] as? Bool,
              let afterZSleepDelay = value["afterZSleepDelay"] as? Int else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoWood settings.")
        }
        return .init(roundNum: roundNum, dailyMaxCount: dailyMaxCount,
                     useWonderlandRefresh: useWonderlandRefresh,
                     woodCountOcrEnabled: woodCountOcrEnabled,
                     afterZSleepDelay: afterZSleepDelay)
    }

    private func decodeAutoMusicGameSettings(_ value: Any) throws
        -> BetterGICoreAutoMusicGameSettings {
        guard let value = value as? [String: Any],
              value["name"] as? String == "AutoMusicGame",
              let mustCanorusLevel = value["mustCanorusLevel"] as? Bool,
              let musicLevel = value["musicLevel"] as? String,
              let options = value["musicLevelOptions"] as? [String] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoMusicGame settings.")
        }
        return .init(mustCanorusLevel: mustCanorusLevel, musicLevel: musicLevel,
                     musicLevelOptions: options)
    }

    private func decodeAutoBossSettings(_ value: Any) throws -> BetterGICoreAutoBossSettings {
        guard let value = value as? [String: Any], value["name"] as? String == "AutoBoss",
              let bossName = value["bossName"] as? String,
              let bossOptions = value["bossOptions"] as? [String],
              let strategyName = value["strategyName"] as? String,
              let strategyOptions = value["strategyOptions"] as? [String],
              let teamName = value["teamName"] as? String,
              let specifyRunCount = value["specifyRunCount"] as? Bool,
              let runCount = value["runCount"] as? Int,
              let useTransientResin = value["useTransientResin"] as? Bool,
              let useFragileResin = value["useFragileResin"] as? Bool,
              let returnToStatue = value["returnToStatueAfterEachRound"] as? Bool,
              let rewardRecognition = value["rewardRecognitionEnabled"] as? Bool,
              let reviveRetryCount = value["reviveRetryCount"] as? Int else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoBoss settings.")
        }
        return .init(bossName: bossName, bossOptions: bossOptions,
                     strategyName: strategyName, strategyOptions: strategyOptions,
                     teamName: teamName, specifyRunCount: specifyRunCount,
                     runCount: runCount, useTransientResin: useTransientResin,
                     useFragileResin: useFragileResin,
                     returnToStatueAfterEachRound: returnToStatue,
                     rewardRecognitionEnabled: rewardRecognition,
                     reviveRetryCount: reviveRetryCount)
    }

    private func decodeAutoDomainSettings(_ value: Any) throws -> BetterGICoreAutoDomainSettings {
        guard let value = value as? [String: Any], value["name"] as? String == "AutoDomain",
              let strategyName = value["strategyName"] as? String,
              let strategyOptions = value["strategyOptions"] as? [String],
              let partyName = value["partyName"] as? String,
              let domainName = value["domainName"] as? String,
              let domainOptions = value["domainOptions"] as? [String],
              let specifyResinUse = value["specifyResinUse"] as? Bool,
              let original = value["originalResinUseCount"] as? Int,
              let condensed = value["condensedResinUseCount"] as? Int,
              let transient = value["transientResinUseCount"] as? Int,
              let fragile = value["fragileResinUseCount"] as? Int,
              let salvage = value["autoArtifactSalvage"] as? Bool,
              let maxStar = value["maxArtifactStar"] as? String,
              let starOptions = value["maxArtifactStarOptions"] as? [String],
              let fightEndDelay = value["fightEndDelay"] as? Double,
              let shortMovement = value["shortMovement"] as? Bool,
              let walkToF = value["walkToF"] as? Bool,
              let moveTimes = value["leftRightMoveTimes"] as? Int,
              let autoEat = value["autoEat"] as? Bool,
              let rewardRecognition = value["rewardRecognitionEnabled"] as? Bool,
              let reviveRetryCount = value["reviveRetryCount"] as? Int else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoDomain settings.")
        }
        return .init(strategyName: strategyName, strategyOptions: strategyOptions,
                     partyName: partyName, domainName: domainName, domainOptions: domainOptions,
                     specifyResinUse: specifyResinUse, originalResinUseCount: original,
                     condensedResinUseCount: condensed, transientResinUseCount: transient,
                     fragileResinUseCount: fragile, autoArtifactSalvage: salvage,
                     maxArtifactStar: maxStar, maxArtifactStarOptions: starOptions,
                     fightEndDelay: fightEndDelay, shortMovement: shortMovement,
                     walkToF: walkToF, leftRightMoveTimes: moveTimes, autoEat: autoEat,
                     rewardRecognitionEnabled: rewardRecognition,
                     reviveRetryCount: reviveRetryCount)
    }

    private func decodeAutoLeyLineOutcropSettings(_ value: Any) throws
        -> BetterGICoreAutoLeyLineOutcropSettings {
        guard let value = value as? [String: Any],
              value["name"] as? String == "AutoLeyLineOutcrop",
              let leyLineOutcropType = value["leyLineOutcropType"] as? String,
              let leyLineOutcropTypeOptions = value["leyLineOutcropTypeOptions"] as? [String],
              let country = value["country"] as? String,
              let countryOptions = value["countryOptions"] as? [String],
              let strategyName = value["strategyName"] as? String,
              let strategyOptions = value["strategyOptions"] as? [String],
              let actionSchedulerByCd = value["actionSchedulerByCd"] as? String,
              let seekEnemyEnabled = value["seekEnemyEnabled"] as? Bool,
              let seekEnemyRotaryFactor = value["seekEnemyRotaryFactor"] as? Int,
              let seekEnemyIntervalSeconds = value["seekEnemyIntervalSeconds"] as? Int,
              let kazuhaPickupEnabled = value["kazuhaPickupEnabled"] as? Bool,
              let qinDoublePickUp = value["qinDoublePickUp"] as? Bool,
              let scanDropsAfterRewardEnabled = value["scanDropsAfterRewardEnabled"] as? Bool,
              let scanDropsAfterRewardSeconds = value["scanDropsAfterRewardSeconds"] as? Int,
              let isResinExhaustionMode = value["isResinExhaustionMode"] as? Bool,
              let openModeCountMin = value["openModeCountMin"] as? Bool,
              let count = value["count"] as? Int,
              let useTransientResin = value["useTransientResin"] as? Bool,
              let useFragileResin = value["useFragileResin"] as? Bool,
              let team = value["team"] as? String,
              let friendshipTeam = value["friendshipTeam"] as? String,
              let timeout = value["timeout"] as? Int,
              let useAdventurerHandbook = value["useAdventurerHandbook"] as? Bool,
              let isNotification = value["isNotification"] as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoLeyLineOutcrop settings.")
        }
        return .init(
            leyLineOutcropType: leyLineOutcropType,
            leyLineOutcropTypeOptions: leyLineOutcropTypeOptions,
            country: country, countryOptions: countryOptions,
            strategyName: strategyName, strategyOptions: strategyOptions,
            actionSchedulerByCd: actionSchedulerByCd,
            seekEnemyEnabled: seekEnemyEnabled,
            seekEnemyRotaryFactor: seekEnemyRotaryFactor,
            seekEnemyIntervalSeconds: seekEnemyIntervalSeconds,
            kazuhaPickupEnabled: kazuhaPickupEnabled,
            qinDoublePickUp: qinDoublePickUp,
            scanDropsAfterRewardEnabled: scanDropsAfterRewardEnabled,
            scanDropsAfterRewardSeconds: scanDropsAfterRewardSeconds,
            isResinExhaustionMode: isResinExhaustionMode,
            openModeCountMin: openModeCountMin, count: count,
            useTransientResin: useTransientResin, useFragileResin: useFragileResin,
            team: team, friendshipTeam: friendshipTeam, timeout: timeout,
            useAdventurerHandbook: useAdventurerHandbook,
            isNotification: isNotification)
    }

    private func decodeAutoStygianOnslaughtSettings(_ value: Any) throws
        -> BetterGICoreAutoStygianOnslaughtSettings {
        guard let value = value as? [String: Any],
              value["name"] as? String == "AutoStygianOnslaught",
              let strategyName = value["strategyName"] as? String,
              let strategyOptions = value["strategyOptions"] as? [String],
              let bossNum = value["bossNum"] as? Int,
              let bossNumOptions = value["bossNumOptions"] as? [Int],
              let fightTeamName = value["fightTeamName"] as? String,
              let specifyResinUse = value["specifyResinUse"] as? Bool,
              let originalResinUseCount = value["originalResinUseCount"] as? Int,
              let condensedResinUseCount = value["condensedResinUseCount"] as? Int,
              let transientResinUseCount = value["transientResinUseCount"] as? Int,
              let fragileResinUseCount = value["fragileResinUseCount"] as? Int,
              let autoArtifactSalvage = value["autoArtifactSalvage"] as? Bool,
              let maxArtifactStar = value["maxArtifactStar"] as? String,
              let maxArtifactStarOptions = value["maxArtifactStarOptions"] as? [String] else {
            throw BetterGICoreRPCError.protocolViolation(
                "Invalid AutoStygianOnslaught settings.")
        }
        return .init(
            strategyName: strategyName, strategyOptions: strategyOptions,
            bossNum: bossNum, bossNumOptions: bossNumOptions,
            fightTeamName: fightTeamName, specifyResinUse: specifyResinUse,
            originalResinUseCount: originalResinUseCount,
            condensedResinUseCount: condensedResinUseCount,
            transientResinUseCount: transientResinUseCount,
            fragileResinUseCount: fragileResinUseCount,
            autoArtifactSalvage: autoArtifactSalvage,
            maxArtifactStar: maxArtifactStar,
            maxArtifactStarOptions: maxArtifactStarOptions)
    }

    private func decodeAutoArtifactSalvageSettings(_ value: Any) throws
        -> BetterGICoreAutoArtifactSalvageSettings {
        guard let value = value as? [String: Any],
              value["name"] as? String == "AutoArtifactSalvage",
              let javaScript = value["javaScript"] as? String,
              let artifactSetFilter = value["artifactSetFilter"] as? String,
              let maxArtifactStar = value["maxArtifactStar"] as? String,
              let maxArtifactStarOptions = value["maxArtifactStarOptions"] as? [String],
              let maxNumToCheck = value["maxNumToCheck"] as? Int,
              let recognitionFailurePolicy = value["recognitionFailurePolicy"] as? String,
              let rawOptions = value["recognitionFailurePolicyOptions"] as? [[String: Any]] else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoArtifactSalvage settings.")
        }
        let options = try rawOptions.map { option -> BetterGICoreNamedOption in
            guard let optionValue = option["value"] as? String,
                  let displayName = option["displayName"] as? String else {
                throw BetterGICoreRPCError.protocolViolation(
                    "Invalid AutoArtifactSalvage recognition policy option.")
            }
            return .init(value: optionValue, displayName: displayName)
        }
        return .init(javaScript: javaScript, artifactSetFilter: artifactSetFilter,
                     maxArtifactStar: maxArtifactStar,
                     maxArtifactStarOptions: maxArtifactStarOptions,
                     maxNumToCheck: maxNumToCheck,
                     recognitionFailurePolicy: recognitionFailurePolicy,
                     recognitionFailurePolicyOptions: options)
    }

    private func decodeAutoFightSettings(_ value: Any) throws -> BetterGICoreAutoFightSettings {
        guard let value = value as? [String: Any], value["name"] as? String == "AutoFight",
              let strategyName = value["strategyName"] as? String,
              let strategyOptions = value["strategyOptions"] as? [String],
              let actionSchedulerByCd = value["actionSchedulerByCd"] as? String,
              let fightFinishDetectEnabled = value["fightFinishDetectEnabled"] as? Bool,
              let fastCheckEnabled = value["fastCheckEnabled"] as? Bool,
              let fastCheckParams = value["fastCheckParams"] as? String,
              let rotateFindEnemyEnabled = value["rotateFindEnemyEnabled"] as? Bool,
              let rotaryFactor = value["rotaryFactor"] as? Int,
              let checkBeforeBurst = value["checkBeforeBurst"] as? Bool,
              let isFirstCheck = value["isFirstCheck"] as? Bool,
              let checkEndDelay = value["checkEndDelay"] as? String,
              let beforeDetectDelay = value["beforeDetectDelay"] as? String,
              let guardianAvatar = value["guardianAvatar"] as? String,
              let guardianAvatarOptions = value["guardianAvatarOptions"] as? [String],
              let guardianCombatSkip = value["guardianCombatSkip"] as? Bool,
              let burstEnabled = value["burstEnabled"] as? Bool,
              let guardianAvatarHold = value["guardianAvatarHold"] as? Bool,
              let pickDropsAfterFightEnabled = value["pickDropsAfterFightEnabled"] as? Bool,
              let pickDropsAfterFightSeconds = value["pickDropsAfterFightSeconds"] as? Int,
              let kazuhaPickupEnabled = value["kazuhaPickupEnabled"] as? Bool,
              let qinDoublePickUp = value["qinDoublePickUp"] as? Bool,
              let expBasedPickupEnabled = value["expBasedPickupEnabled"] as? Bool,
              let timeout = value["timeout"] as? Int,
              let swimmingEnabled = value["swimmingEnabled"] as? Bool else {
            throw BetterGICoreRPCError.protocolViolation("Invalid AutoFight settings.")
        }
        return .init(strategyName: strategyName, strategyOptions: strategyOptions,
                     actionSchedulerByCd: actionSchedulerByCd,
                     fightFinishDetectEnabled: fightFinishDetectEnabled,
                     fastCheckEnabled: fastCheckEnabled, fastCheckParams: fastCheckParams,
                     rotateFindEnemyEnabled: rotateFindEnemyEnabled, rotaryFactor: rotaryFactor,
                     checkBeforeBurst: checkBeforeBurst, isFirstCheck: isFirstCheck,
                     checkEndDelay: checkEndDelay, beforeDetectDelay: beforeDetectDelay,
                     guardianAvatar: guardianAvatar, guardianAvatarOptions: guardianAvatarOptions,
                     guardianCombatSkip: guardianCombatSkip, burstEnabled: burstEnabled,
                     guardianAvatarHold: guardianAvatarHold,
                     pickDropsAfterFightEnabled: pickDropsAfterFightEnabled,
                     pickDropsAfterFightSeconds: pickDropsAfterFightSeconds,
                     kazuhaPickupEnabled: kazuhaPickupEnabled, qinDoublePickUp: qinDoublePickUp,
                     expBasedPickupEnabled: expBasedPickupEnabled, timeout: timeout,
                     swimmingEnabled: swimmingEnabled)
    }

    func startSoloTask(name: String, inputText: String? = nil) throws
        -> BetterGICoreSoloTaskStatus {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        var parameters: [String: Any] = ["name": name]
        if let inputText { parameters["inputText"] = inputText }
        let result = try client.request(method: "solo.start", parameters: parameters)
        return try Self.decodeSoloTaskStatus(result)
    }

    func stopSoloTask(taskID: String) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        _ = try client.request(method: "solo.stop", parameters: ["taskId": taskID])
    }

    func soloTaskStatus() throws -> BetterGICoreSoloTaskStatus {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        return try Self.decodeSoloTaskStatus(try client.request(method: "solo.status"))
    }

    private static func decodeSoloTaskStatus(_ value: Any?) throws -> BetterGICoreSoloTaskStatus {
        guard let result = value as? [String: Any], let state = result["state"] as? String else {
            throw BetterGICoreRPCError.protocolViolation("Invalid solo task status.")
        }
        return BetterGICoreSoloTaskStatus(
            taskID: result["taskId"] as? String,
            name: result["name"] as? String,
            state: state,
            error: result["error"] as? String
        )
    }

    func stopScheduler(taskID: String) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        _ = try client.request(method: "scheduler.stop", parameters: ["taskId": taskID])
    }

    func pauseScheduler(taskID: String) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        _ = try client.request(method: "scheduler.pause", parameters: ["taskId": taskID])
    }

    func resumeScheduler(taskID: String) throws {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        _ = try client.request(method: "scheduler.resume", parameters: ["taskId": taskID])
    }

    func stop() {
        intentionalStop = true
        if let client {
            _ = try? client.request(method: "core.shutdown")
            client.disconnect()
        }
        if let process, process.isRunning { process.terminate() }
        callbackClient?.stop()
        callbackTask?.cancel()
        process = nil
        client = nil
        callbackClient = nil
        callbackTask = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        state = .stopped
    }

    private func processTerminated(generation: Int) async {
        guard generation == processGeneration, !intentionalStop else { return }
        guard case .running = state else { return }

        client?.disconnect()
        callbackClient?.stop()
        callbackTask?.cancel()
        process = nil
        client = nil
        callbackClient = nil
        callbackTask = nil
        state = .failed("BetterGI Core exited unexpectedly.")
        progressHandler?(.failed("BetterGI Core exited unexpectedly."))

        guard controlledRestartCount == 0,
              let platformHandler, let progressHandler, let logHandler else { return }
        controlledRestartCount = 1
        do {
            _ = try await start(
                progressHandler: progressHandler,
                logHandler: logHandler,
                platformHandler: platformHandler
            )
        } catch {
            state = .failed("BetterGI Core controlled restart failed: \(error.localizedDescription)")
        }
    }

    private func callbackFailed(_ error: Error) {
        guard case .running = state else { return }
        state = .failed("Core platform callback failed: \(error.localizedDescription)")
        progressHandler?(.failed("Core platform callback failed: \(error.localizedDescription)"))
    }

    private func waitForSocket(_ socketURL: URL, process: Process) async throws {
        for _ in 0..<Self.startupPollLimit {
            guard process.isRunning else {
                throw BetterGICoreRPCError.socket("BetterGI Core exited before creating its RPC socket.")
            }
            if FileManager.default.fileExists(atPath: socketURL.path) { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw BetterGICoreRPCError.socket("Timed out waiting for BetterGI Core RPC socket.")
    }

    private static func stopProcess(_ process: Process) async {
        guard process.isRunning else { return }
        process.terminate()
        for _ in 0..<80 {
            if !process.isRunning { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    private nonisolated static func resolveExecutableURL() throws -> URL {
        if let configured = ProcessInfo.processInfo.environment["BETTERGI_CORE_HOST"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        if let bundled = Bundle.main.executableURL?
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/BetterGICore/BetterGenshinImpact.Core.Host"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
#if DEBUG
        if let appExecutableURL = Bundle.main.executableURL,
           let development = resolveDevelopmentExecutableURL(from: appExecutableURL) {
            return development
        }
#endif
        throw BetterGICoreRPCError.socket(
            "BetterGI Core Host is not bundled. Set BETTERGI_CORE_HOST for development builds."
        )
    }

    static func resolveDevelopmentExecutableURL(from appExecutableURL: URL) -> URL? {
        var directory = appExecutableURL.deletingLastPathComponent()
        while directory.path != "/" {
            if directory.lastPathComponent == ".build" {
                let candidate = directory
                    .appendingPathComponent("BetterGICore", isDirectory: true)
                    .appendingPathComponent("BetterGenshinImpact.Core.Host")
                return FileManager.default.isExecutableFile(atPath: candidate.path)
                    ? candidate
                    : nil
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private static func makeSessionToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private final class CoreOutputForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private let handler: @Sendable (String) -> Void

    init(handler: @escaping @Sendable (String) -> Void) {
        self.handler = handler
    }

    func consume(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
        let lines = lock.withLock { () -> [String] in
            pending += chunk
            var parts = pending.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            pending = parts.removeLast()
            return parts
        }
        for line in lines where !line.isEmpty {
            handler(line)
        }
    }
}
