import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("RustCoreBridge AutoSkip decision mapping")
struct RustCoreBridgeAutoSkipDecisionTests {
    @MainActor
    @Test("AutoSkip click option decision maps target observation to absolute click point")
    func autoSkipClickOptionDecisionMapsTargetObservationToAbsoluteClickPoint() throws {
        let dylibPath = localRustDylibPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            return
        }

        let bridge = try RustCoreBridge(libraryPath: dylibPath)
        let frame = makeFrame(windowFrame: CGRect(x: 100, y: 200, width: 960, height: 540))
        let observations = [
            makeObservation(
                id: "option-1",
                rect: CGRect(x: 0.10, y: 0.20, width: 0.05, height: 0.10),
                frame: frame
            ),
            makeObservation(
                id: "option-2",
                rect: CGRect(x: 0.10, y: 0.50, width: 0.05, height: 0.10),
                frame: frame
            )
        ]

        let decision = try #require(bridge.evaluateAutoSkipDecision(
            frame: frame,
            observations: observations,
            recognitionObjects: RecognitionObject.bgiAutoSkipObjects,
            currentGameUiCategory: .talk,
            keyBindings: .bgiDefault
        ))

        #expect(decision.observationIDs == ["option-1"])
        let action = try #require(decision.actions.first)
        guard case let .leftClick(point?) = action else {
            Issue.record("Expected AutoSkip click option to map to a concrete leftClick point")
            return
        }
        #expect(abs(point.x - 220) < 0.001)
        #expect(abs(point.y - 335) < 0.001)
    }

    @MainActor
    @Test("AutoSkip daily reward option maps to its own observation click point")
    func autoSkipDailyRewardOptionMapsToItsOwnObservationClickPoint() throws {
        let dylibPath = localRustDylibPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            return
        }

        let bridge = try RustCoreBridge(libraryPath: dylibPath)
        let frame = makeFrame(windowFrame: CGRect(x: 100, y: 200, width: 960, height: 540))
        let observations = [
            makeObservation(
                id: "generic-option",
                rect: CGRect(x: 0.10, y: 0.20, width: 0.05, height: 0.10),
                frame: frame
            ),
            makeObservation(
                id: "daily-option",
                objectID: "AutoSkip.DailyRewardIconRo",
                objectName: "DailyRewardIcon",
                rect: CGRect(x: 0.20, y: 0.60, width: 0.04, height: 0.08),
                frame: frame
            )
        ]

        let decision = try #require(bridge.evaluateAutoSkipDecision(
            frame: frame,
            observations: observations,
            recognitionObjects: RecognitionObject.bgiAutoSkipObjects,
            currentGameUiCategory: .talk,
            keyBindings: .bgiDefault
        ))

        #expect(decision.observationIDs == ["daily-option"])
        let action = try #require(decision.actions.first)
        guard case let .leftClick(point?) = action else {
            Issue.record("Expected AutoSkip daily reward option to map to a concrete leftClick point")
            return
        }
        #expect(abs(point.x - 311.2) < 0.001)
        #expect(abs(point.y - 545.6) < 0.001)
    }

    @MainActor
    @Test("AutoSkip click decision is dropped when target rect cannot resolve to a safe point")
    func autoSkipClickDecisionIsDroppedWhenTargetRectCannotResolveToSafePoint() throws {
        let dylibPath = localRustDylibPath()
        guard FileManager.default.fileExists(atPath: dylibPath) else {
            return
        }

        let bridge = try RustCoreBridge(libraryPath: dylibPath)
        let frame = makeFrame(windowFrame: CGRect(x: 100, y: 200, width: 960, height: 540))
        let observations = [
            makeObservation(
                id: "option-outside",
                rect: CGRect(x: 1.2, y: 0.20, width: 0.05, height: 0.10),
                frame: frame
            )
        ]

        let decision = bridge.evaluateAutoSkipDecision(
            frame: frame,
            observations: observations,
            recognitionObjects: RecognitionObject.bgiAutoSkipObjects,
            currentGameUiCategory: .talk,
            keyBindings: .bgiDefault
        )

        #expect(decision == nil)
    }

    private func localRustDylibPath() -> String {
        if let path = ProcessInfo.processInfo.environment["MACGI_CORE_DYLIB"], !path.isEmpty {
            return path
        }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return repoRoot
            .appendingPathComponent("macgi-core/target/debug/libmacgi_core.dylib")
            .path
    }

    private func makeFrame(windowFrame: CGRect) -> CapturedFrame {
        let window = WindowInfo(
            id: 42,
            ownerPID: 10,
            ownerName: "wine",
            title: "原神",
            frame: windowFrame,
            layer: 0,
            isOnScreen: true,
            scaleFactor: 1
        )
        return CapturedFrame(
            frameIndex: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            width: Int(windowFrame.width),
            height: Int(windowFrame.height),
            scaleFactor: 1,
            pixelFormat: 0x42475241,
            bytesPerRow: Int(windowFrame.width) * 4,
            sourceWindow: window
        )
    }

    private func makeObservation(
        id: String,
        objectID: String = "AutoSkip.OptionIconRo",
        objectName: String = "OptionIcon",
        rect: CGRect,
        frame: CapturedFrame
    ) -> RecognitionObservation {
        RecognitionObservation(
            id: id,
            objectID: objectID,
            objectName: objectName,
            recognitionType: .templateMatch,
            normalizedRect: rect,
            confidence: 0.99,
            text: nil,
            frameIndex: frame.frameIndex,
            timestamp: frame.timestamp
        )
    }
}
