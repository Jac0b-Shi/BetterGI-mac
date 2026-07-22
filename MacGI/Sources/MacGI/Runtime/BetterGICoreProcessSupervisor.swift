import Darwin
import Foundation
import Security

struct BetterGICoreTriggerState: Sendable, Equatable {
    let name: String
    let displayName: String
    let enabled: Bool
    let priority: Int
    let exclusive: Bool
}

struct BetterGICoreSoloTask: Sendable, Equatable, Identifiable {
    let name: String
    let displayName: String
    let available: Bool
    let unavailableReason: String?
    let settingsAvailable: Bool
    var id: String { name }
}

struct BetterGICoreAutoCookSettings: Sendable, Equatable {
    let checkIntervalMs: Int
    let stopTaskWhenRecoverButtonDetected: Bool
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
                  let priority = item["priority"] as? Int,
                  let exclusive = item["exclusive"] as? Bool else {
                throw BetterGICoreRPCError.protocolViolation("Invalid trigger state.")
            }
            return BetterGICoreTriggerState(
                name: name, displayName: displayName, enabled: enabled,
                priority: priority, exclusive: exclusive
            )
        }
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
                  let available = item["available"] as? Bool else {
                throw BetterGICoreRPCError.protocolViolation("Invalid solo task descriptor.")
            }
            return BetterGICoreSoloTask(
                name: name, displayName: displayName, available: available,
                unavailableReason: item["unavailableReason"] as? String,
                settingsAvailable: item["settingsAvailable"] as? Bool ?? false
            )
        }
    }

    func autoCookSettings() throws -> BetterGICoreAutoCookSettings {
        try decodeAutoCookSettings(requestSoloSettings(
            method: "solo.settings.get", parameters: ["name": "AutoCook"]
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

    func startSoloTask(name: String) throws -> BetterGICoreSoloTaskStatus {
        guard case .running = state, let client else {
            throw BetterGICoreRPCError.socket("BetterGI Core is not running.")
        }
        let result = try client.request(method: "solo.start", parameters: ["name": name])
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
