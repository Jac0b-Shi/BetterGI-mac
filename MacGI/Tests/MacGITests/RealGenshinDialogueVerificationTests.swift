import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import MacGI
import Testing

@Suite("Real Genshin dialogue verification")
struct RealGenshinDialogueVerificationTests {
    @MainActor
    @Test("Capture current Genshin dialogue frame and run AutoSkip recognition diagnostics")
    func captureCurrentDialogueFrameAndRunAutoSkipDiagnostics() throws {
        guard ProcessInfo.processInfo.environment["MACGI_RUN_REAL_WINDOW_TESTS"] == "1" else {
            return
        }

        let windows = QuartzWindowEnumerator.enumerateApplicationWindows()
        let window = try #require(QuartzWindowEnumerator.bestGameWindow(from: windows))
        #expect(window.isLikelyGameWindow)

        let imageFrame = try QuartzWindowImageFrameProvider().captureWindow(window)
        let outputURL = outputPNGURL()
        try savePNG(imageFrame.cgImage, to: outputURL)

        let autoSkipObjects = RecognitionObject.bgiP0Defaults.filter {
            $0.featureID == "auto-dialog" && $0.isEnabled
        }
        let templateObjects = autoSkipObjects.filter { $0.recognitionType == .templateMatch }
        let swiftTemplateReport = TemplateMatchingRecognitionEngine().recognize(
            imageFrame: imageFrame,
            objects: templateObjects
        )
        let rustTemplateReport = RustCoreBridge.loadDefault()?.recognizeTemplates(
            imageFrame: imageFrame,
            objects: templateObjects
        )

        let runtime = try PaddleOCRRuntime()
        let ocrEngine = try PaddleOCRRecognitionEngine(runtime: runtime)
        let autoSkipOCRReport = ocrEngine.recognize(
            imageFrame: imageFrame,
            objects: autoSkipObjects.filter { $0.recognitionType != .templateMatch }
        )
        let fullFrameOCRReport = ocrEngine.recognize(
            imageFrame: imageFrame,
            objects: [
                RecognitionObject(
                    id: "RealGenshin.Dialogue.FullFrameOCR",
                    recognitionType: .ocr,
                    name: "FullFrameOCR",
                    featureID: "auto-dialog"
                )
            ]
        )

        let primaryTemplateObservations = rustTemplateReport?.observations ?? swiftTemplateReport.observations
        let activeObservations = primaryTemplateObservations + autoSkipOCRReport.observations
        let autoSkipDecision = RustCoreBridge.loadDefault()?.evaluateAutoSkipDecision(
            frame: imageFrame.metadata,
            observations: activeObservations,
            recognitionObjects: autoSkipObjects,
            currentGameUiCategory: .talk,
            keyBindings: .bgiDefault
        )
        let objectByID = Dictionary(uniqueKeysWithValues: autoSkipObjects.map { ($0.id, $0) })
        let dialogueOptionObservations = primaryTemplateObservations.filter { observation in
            objectByID[observation.objectID]?.tags.contains("DialogueOption") == true
        }
        let dailyRewardObservations = primaryTemplateObservations.filter {
            $0.objectID == "AutoSkip.DailyRewardIconRo"
        }
        let fullFrameText = fullFrameOCRReport.observations.compactMap(\.text).joined(separator: " ")
        let dialogueTextEvidence = ["凯瑟琳", "冒险", "协会", "委托"].contains { fullFrameText.contains($0) }

        print(
            """
            Real Genshin dialogue verification:
              window: \(window.displayName) id=\(window.id) frame=\(window.frame)
              capture: \(imageFrame.backendName) \(imageFrame.metadata.sizeDescription) scale=\(String(format: "%.2f", imageFrame.metadata.scaleFactor))
              savedPNG: \(outputURL.path)
              swiftTemplate: objects=\(swiftTemplateReport.objectCount) matches=\(swiftTemplateReport.matchedCount) \(summarize(swiftTemplateReport.observations))
              rustTemplate: \(rustTemplateReport.map { "objects=\($0.objectCount) matches=\($0.matchedCount) \(summarize($0.observations))" } ?? "unavailable")
              autoSkipOCR: objects=\(autoSkipOCRReport.objectCount) matches=\(autoSkipOCRReport.matchedCount) errors=\(autoSkipOCRReport.errors)
              fullFrameOCR: objects=\(fullFrameOCRReport.objectCount) matches=\(fullFrameOCRReport.matchedCount) text=\(fullFrameText)
              rustAutoSkipDecision: \(autoSkipDecision.map { "reason=\($0.reason) actions=\($0.actions.map(\.displayName)) observations=\($0.observationIDs)" } ?? "unavailable")
            """
        )

        #expect(!dialogueOptionObservations.isEmpty || dialogueTextEvidence)
        if dialogueOptionObservations.isEmpty {
            #expect(autoSkipDecision?.actions == [.keyPress(key: .space)])
        }
        if let dailyReward = dailyRewardObservations.first {
            #expect(autoSkipDecision?.observationIDs.contains(dailyReward.id) == true)
        }
    }

    private func outputPNGURL() -> URL {
        if let configuredPath = ProcessInfo.processInfo.environment["MACGI_REAL_FRAME_OUTPUT"], !configuredPath.isEmpty {
            return URL(fileURLWithPath: configuredPath)
        }
        return URL(fileURLWithPath: "/tmp/bettergi-mac-real-genshin-dialogue.png")
    }

    private func savePNG(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func summarize(_ observations: [RecognitionObservation]) -> String {
        observations
            .sorted { left, right in
                if left.objectID != right.objectID {
                    return left.objectID < right.objectID
                }
                if left.normalizedRect.minY != right.normalizedRect.minY {
                    return left.normalizedRect.minY < right.normalizedRect.minY
                }
                return left.normalizedRect.minX < right.normalizedRect.minX
            }
            .map { observation in
                let rect = observation.normalizedRect
                return "\(observation.objectID)@\(String(format: "%.3f", observation.confidence))[\(String(format: "%.3f", rect.minX)),\(String(format: "%.3f", rect.minY)),\(String(format: "%.3f", rect.width)),\(String(format: "%.3f", rect.height))]"
            }
            .joined(separator: ", ")
    }
}
