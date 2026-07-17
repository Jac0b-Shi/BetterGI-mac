import Foundation

struct BGIMainUIStatusChecker {
    typealias RecognitionObjectProvider = @MainActor (CaptureImageFrame, RecognitionObject) async throws -> [RecognitionObservation]

    var statusRecognizer: BGIGameUIStatusRecognizer = BGIGameUIStatusRecognizer()
    var templateRecognitionEngine: TemplateMatchingRecognitionEngine = TemplateMatchingRecognitionEngine()
    var recognitionObjectProvider: RecognitionObjectProvider?

    func isInMainUI(frame: CaptureImageFrame) async throws -> Bool {
        let status = statusRecognizer.recognize(frame)
        guard status.isInMainUI else { return false }
        return !(try await isInRevivePrompt(in: frame))
    }

    private func isInRevivePrompt(in frame: CaptureImageFrame) async throws -> Bool {
        let confirmReport = templateRecognitionEngine.recognize(
            imageFrame: frame,
            objects: [RecognitionObject.bgiAutoFightConfirmObject]
        )
        guard confirmReport.matchedCount > 0, let recognitionObjectProvider else {
            return false
        }

        let observations: [RecognitionObservation]
        do {
            observations = try await recognitionObjectProvider(frame, RecognitionObject.bgiRevivePromptTextObject)
        } catch {
            return false
        }

        return observations
            .compactMap(\.text)
            .map { $0.replacingOccurrences(of: " ", with: "") }
            .contains { text in
                text.contains("复苏") || text.localizedCaseInsensitiveContains("revive")
            }
    }
}
