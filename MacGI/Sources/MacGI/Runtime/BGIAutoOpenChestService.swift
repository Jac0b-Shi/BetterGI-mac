import CoreGraphics
import Foundation

// MARK: - AutoOpenChest (自动开宝箱)

/// Upstream ref: `AutoOpenChestTask.cs` / `AutoOpenChestTrigger.cs`
/// Detects chest F-key icon near a chest and presses interact to open it.
final class BGIAutoOpenChestService: @unchecked Sendable {
    typealias CaptureFrameProvider = @MainActor () async throws -> CaptureImageFrame
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult
    private let captureFrameProvider: CaptureFrameProvider?
    private let inputHandler: InputHandler
    private let templateEngine = TemplateMatchingRecognitionEngine()
    init(inputHandler: @escaping InputHandler, captureFrameProvider: CaptureFrameProvider? = nil) {
        self.inputHandler = inputHandler; self.captureFrameProvider = captureFrameProvider
    }
    func evaluate() async -> Bool {
        guard let provider = captureFrameProvider, let frame = try? await provider() else { return false }
        let results = templateEngine.recognize(imageFrame: frame, objects: RecognitionObject.bgiChestObjects).observations
        if results.contains(where: { $0.objectID.contains("ChestFIcon") }) {
            guard let ia = KeyBindingsConfig.bgiDefault.inputAction(for: .pickUpOrInteract, type: .keyPress) else { return false }
            _ = await inputHandler(ia)
            return true
        }
        return false
    }
}

extension RecognitionObject {
    static let bgiChestFIconObject = RecognitionObject(
        id: "AutoOpenChest.ChestFIconRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 1, coordinateSpace: .normalized),
        name: "ChestFIcon",
        templateAssetName: "GameTask/AutoOpenChest/Assets/1920x1080/chest_F_icon.png",
        threshold: 0.85,
        tags: ["AutoOpenChest"]
    )
    static let bgiChestIconObject = RecognitionObject(
        id: "AutoOpenChest.ChestIconRo",
        recognitionType: .templateMatch,
        regionOfInterest: RecognitionROI(x: 0, y: 0, width: 1, height: 1, coordinateSpace: .normalized),
        name: "ChestIcon",
        templateAssetName: "GameTask/AutoOpenChest/Assets/1920x1080/chest.png",
        threshold: 0.85,
        tags: ["AutoOpenChest"]
    )
    static let bgiChestObjects: [RecognitionObject] = [bgiChestFIconObject, bgiChestIconObject]
}
