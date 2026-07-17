import Foundation

struct BGIJSScriptGenshinCommandReplayResult: Equatable, Sendable {
    struct PendingCommand: Equatable, Sendable {
        var command: BGIJSScriptGenshinCommand
        var reason: String
    }

    struct FailedCommand: Equatable, Sendable {
        var command: BGIJSScriptGenshinCommand
        var message: String
    }

    var executedCommands: [BGIJSScriptGenshinCommand] = []
    var pendingCommands: [PendingCommand] = []
    var failedCommands: [FailedCommand] = []

    var executedCount: Int { executedCommands.count }
    var pendingCount: Int { pendingCommands.count }
    var failedCount: Int { failedCommands.count }
}

@MainActor
final class BGIJSScriptGenshinCommandReplayer {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    typealias CaptureFrameProvider = BGIBigMapInteractionService.CaptureFrameProvider
    typealias RecognitionObjectProvider = BGIBigMapInteractionService.RecognitionObjectProvider
    typealias BigMapPositionProvider = BGIBigMapInteractionService.BigMapPositionProvider
    typealias OCRProvider = BGIChooseTalkOptionService.OCRProvider

    private let keyBindings: KeyBindingsConfig
    private let inputHandler: InputHandler
    private let captureFrameProvider: CaptureFrameProvider?
    private let recognitionObjectProvider: RecognitionObjectProvider?
    private let bigMapPositionProvider: BigMapPositionProvider?
    private let ocrProvider: OCRProvider?
    private let bigMapConfig: BGIBigMapConfig
    private let returnMainUIConfig: BGIReturnMainUIConfig
    private let chooseTalkOptionConfig: BGIChooseTalkOptionConfig
    private let setTimeConfig: BGISetTimeConfig
    private let reloginConfig: BGIExitAndReloginConfig
    private let partySwitchConfig: BGIPartySwitchConfig
    private let autoFishingConfig: BGIAutoFishingConfig

    init(
        keyBindings: KeyBindingsConfig = .bgiDefault,
        bigMapConfig: BGIBigMapConfig = BGIBigMapConfig(),
        returnMainUIConfig: BGIReturnMainUIConfig = BGIReturnMainUIConfig(),
        chooseTalkOptionConfig: BGIChooseTalkOptionConfig = BGIChooseTalkOptionConfig(),
        setTimeConfig: BGISetTimeConfig = BGISetTimeConfig(),
        reloginConfig: BGIExitAndReloginConfig = BGIExitAndReloginConfig(),
        partySwitchConfig: BGIPartySwitchConfig = .default,
        autoFishingConfig: BGIAutoFishingConfig = .default,
        captureFrameProvider: CaptureFrameProvider? = nil,
        recognitionObjectProvider: RecognitionObjectProvider? = nil,
        bigMapPositionProvider: BigMapPositionProvider? = nil,
        ocrProvider: OCRProvider? = nil,
        inputHandler: @escaping InputHandler
    ) {
        self.keyBindings = keyBindings
        self.bigMapConfig = bigMapConfig
        self.returnMainUIConfig = returnMainUIConfig
        self.chooseTalkOptionConfig = chooseTalkOptionConfig
        self.setTimeConfig = setTimeConfig
        self.reloginConfig = reloginConfig
        self.partySwitchConfig = partySwitchConfig
        self.autoFishingConfig = autoFishingConfig
        self.captureFrameProvider = captureFrameProvider
        self.recognitionObjectProvider = recognitionObjectProvider
        self.bigMapPositionProvider = bigMapPositionProvider
        self.ocrProvider = ocrProvider
        self.inputHandler = inputHandler
    }

    func replay(
        _ commands: [BGIJSScriptGenshinCommand],
        targetWindow: WindowInfo
    ) async -> BGIJSScriptGenshinCommandReplayResult {
        var result = BGIJSScriptGenshinCommandReplayResult()
        for command in commands {
            do {
                switch command {
                case let .teleport(x, y, mapName, force):
                    guard force == true else {
                        result.pendingCommands.append(.init(
                            command: command,
                            reason: "Non-force Tp still requires upstream GetBigMapRect/GetPositionFromBigMap teleport viewport support"
                        ))
                        continue
                    }
                    try await bigMapService(for: targetWindow, mapName: mapName).teleport(tpX: x, tpY: y, mapName: mapName ?? "Teyvat", force: force ?? false)
                    result.executedCommands.append(command)
                case .uid,
                     .getBigMapZoomLevel,
                     .getPositionFromBigMap,
                     .getPositionFromMap,
                     .getCameraOrientation,
                     .clearPartyCache:
                    continue
                case .returnMainUI:
                    try await returnMainUIService().returnToMainUI()
                    result.executedCommands.append(command)
                case let .chooseTalkOption(option, skipTimes, isOrange):
                    try await chooseTalkOptionService().selectText(option, skipTimes: skipTimes, isOrange: isOrange)
                    result.executedCommands.append(command)
                case let .setTime(hour, minute, skip):
                    try await setTimeService(for: targetWindow).setTime(hour: hour, minute: minute, skipAnimation: skip)
                    result.executedCommands.append(command)
                case .relogin:
                    try await exitAndReloginService(for: targetWindow).exitAndRelogin()
                    result.executedCommands.append(command)
                case let .setBigMapZoomLevel(zoomLevel):
                    try await bigMapService(for: targetWindow, mapName: nil).setBigMapZoomLevel(zoomLevel)
                    result.executedCommands.append(command)
                case let .moveMapTo(x, y, _):
                    guard bigMapPositionProvider != nil else {
                        result.pendingCommands.append(.init(
                            command: command,
                            reason: "MoveMapTo requires upstream big-map SIFT position provider"
                        ))
                        continue
                    }
                    try await bigMapService(for: targetWindow, mapName: "Teyvat").moveMapTo(x: x, y: y, mapName: "Teyvat")
                    result.executedCommands.append(command)
                case let .moveIndependentMapTo(x, y, mapName, _):
                    guard bigMapPositionProvider != nil else {
                        result.pendingCommands.append(.init(
                            command: command,
                            reason: "MoveIndependentMapTo requires upstream big-map SIFT position provider"
                        ))
                        continue
                    }
                    try await bigMapService(for: targetWindow, mapName: mapName).moveMapTo(
                        x: Double(x),
                        y: Double(y),
                        mapName: mapName
                    )
                    result.executedCommands.append(command)
                case .teleportToStatueOfTheSeven:
                    result.pendingCommands.append(.init(
                        command: command,
                        reason: "TpToStatueOfTheSeven still requires upstream GetBigMapRect/GetPositionFromBigMap teleport viewport support"
                    ))
                case let .switchParty(partyName):
                    _ = try await partySwitchService(for: targetWindow).switchParty(to: partyName)
                    result.executedCommands.append(command)
                case .autoFishing:
                    await autoFishingService(for: targetWindow).startFishing()
                    result.executedCommands.append(command)
                }
            } catch {
                result.failedCommands.append(.init(
                    command: command,
                    message: error.localizedDescription
                ))
            }
        }
        return result
    }

    private func bigMapService(
        for targetWindow: WindowInfo,
        mapName: String?
    ) -> BGIBigMapInteractionService {
        BGIBigMapInteractionService(
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            recognitionObjectProvider: recognitionObjectProvider,
            bigMapPositionProvider: bigMapPositionProvider,
            keyBindings: keyBindings,
            config: .forWindow(targetWindow, base: bigMapConfig),
            sceneConverter: .forRegion(mapName ?? "Teyvat")
        )
    }

    private func returnMainUIService() -> BGIReturnMainUIService {
        BGIReturnMainUIService(
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            recognitionObjectProvider: recognitionObjectProvider,
            config: returnMainUIConfig
        )
    }

    private func chooseTalkOptionService() -> BGIChooseTalkOptionService {
        BGIChooseTalkOptionService(
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            recognitionObjectProvider: recognitionObjectProvider,
            ocrProvider: ocrProvider,
            config: chooseTalkOptionConfig
        )
    }

    private func setTimeService(for targetWindow: WindowInfo) -> BGISetTimeService {
        BGISetTimeService(
            targetWindow: targetWindow,
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            recognitionObjectProvider: recognitionObjectProvider,
            returnMainUIConfig: returnMainUIConfig,
            config: setTimeConfig
        )
    }

    private func exitAndReloginService(for targetWindow: WindowInfo) -> BGIExitAndReloginService {
        BGIExitAndReloginService(
            targetWindow: targetWindow,
            inputHandler: inputHandler,
            captureFrameProvider: captureFrameProvider,
            recognitionObjectProvider: recognitionObjectProvider,
            config: reloginConfig
        )
    }

    private func partySwitchService(for targetWindow: WindowInfo) -> BGIPartySwitchService {
        _ = targetWindow
        let partyOcr: BGIPartySwitchService.OCRProvider? = if let ocr = ocrProvider {
            { frame, rect in try await ocr(frame, rect).combinedText }
        } else { nil }
        return BGIPartySwitchService(
            inputHandler: inputHandler,
            captureFrameProvider: { [weak self] in
                guard let self, let provider = self.captureFrameProvider else {
                    throw BGIPartySwitchError.cannotFindPartyUI
                }
                return try await provider()
            },
            ocrProvider: partyOcr,
            config: partySwitchConfig
        )
    }

    private func autoFishingService(for targetWindow: WindowInfo) -> BGIAutoFishingService {
        _ = targetWindow
        let fishingOCR: BGIAutoFishingService.OCRProvider? = if let ocr = ocrProvider {
            { frame, rect in try await ocr(frame, rect).combinedText }
        } else { nil }
        return BGIAutoFishingService(
            inputHandler: inputHandler,
            captureFrameProvider: { [weak self] in
                guard let self, let provider = self.captureFrameProvider else {
                    throw BGIYOLOError.inferenceFailed("capture unavailable")
                }
                return try await provider()
            },
            ocrProvider: fishingOCR,
            config: autoFishingConfig
        )
    }
}
