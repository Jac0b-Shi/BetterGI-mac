import Foundation

struct BGIDialogueAudioWaitConfig: Sendable {
    var maxWaitMs: Int = 10000
    var fallbackDelayMs: Int = 2000
    var enabled: Bool = false
    /// macOS: try AVAudioEngine loopback for VAD. Falls back to fixed delay on failure.
    var useLoopbackCapture: Bool = true
    static let `default` = BGIDialogueAudioWaitConfig()
}

/// macOS equivalent of upstream `DialogueOptionAudioWaiter` (279 lines C#).
///
/// Upstream uses Windows WASAPI `ProcessLoopbackAudioCapture`. macOS uses
/// `BGIAVAudioEngineLoopbackCapture` + `BGISileroVADDetector` (silero_vad.onnx).
/// Falls back to fixed delay when audio capture or ONNX model is unavailable.
final class BGIDialogueAudioWaiter: @unchecked Sendable {
    private let config: BGIDialogueAudioWaitConfig
    private let stateLock = NSLock()
    private var waitState: WaiterState?
    private var vadDetector: BGISileroVADDetector?
    private var audioCapture: (any BGIAudioSampleProvider)?

    // Upstream constants from DialogueOptionAudioWaiter.cs
    private static let silenceDurationMs: Double = 2000
    private static let speechRiseMs: Double = 160
    private static let noSpeechQuietMs: Double = 1200
    private static let speechThreshold: Float = 0.60
    private static let maybeSpeechThreshold: Float = 0.35
    private static let speechStartGraceMs: Double = 5000

    var isWaiting: Bool { stateLock.withLock { waitState != nil } }

    init(config: BGIDialogueAudioWaitConfig = .default) {
        self.config = config
        if config.useLoopbackCapture {
            let capture = BGIAVAudioEngineLoopbackCapture()
            audioCapture = capture
            do { try capture.startCapture() } catch { audioCapture = nil }
        }
        do { vadDetector = try BGISileroVADDetector() } catch { vadDetector = nil }
    }

    func start(maxWaitMs: Int = 0, fallbackDelayMs: Int = 0) -> Bool {
        stateLock.withLock {
            guard config.enabled else { return false }
            let max = maxWaitMs > 0 ? maxWaitMs : config.maxWaitMs
            let fallback = fallbackDelayMs > 0 ? fallbackDelayMs : config.fallbackDelayMs

            if vadDetector != nil, audioCapture?.isCapturing == true {
                vadDetector?.reset()
                waitState = .vad(deadline: Date().addingTimeInterval(Double(max) / 1000.0), heardSpeech: false, quietSince: nil)
                return true
            }
            if fallback > 0 {
                waitState = .fallback(deadline: Date().addingTimeInterval(Double(fallback) / 1000.0))
                return true
            }
            return false
        }
    }

    func update() -> Bool {
        stateLock.withLock {
            guard let state = waitState else { return true }
            let now = Date()

            switch state {
            case .fallback(let deadline):
                if now >= deadline { waitState = nil; return true }
                return false

            case .vad(let deadline, var heardSpeech, var quietSince):
                if now >= deadline { waitState = nil; return true }

                guard let detector = vadDetector,
                      let capture = audioCapture else {
                    waitState = nil; return true
                }

                let elapsed = deadline.timeIntervalSinceReferenceDate - now.timeIntervalSinceReferenceDate + Double(config.maxWaitMs)
                let samples = capture.readSamples()
                let prob = detector.update(samples: samples)

                if prob >= Self.speechThreshold {
                    quietSince = nil
                    if elapsed >= Self.speechRiseMs { heardSpeech = true }
                } else if prob <= Self.maybeSpeechThreshold {
                    quietSince = quietSince ?? elapsed
                    let requiredQuiet = heardSpeech ? Self.silenceDurationMs : Self.noSpeechQuietMs
                    if !heardSpeech, elapsed < Self.speechStartGraceMs { return false }
                    if let qs = quietSince, elapsed - qs >= requiredQuiet { waitState = nil; return true }
                }

                waitState = .vad(deadline: deadline, heardSpeech: heardSpeech, quietSince: quietSince)
                return false
            }
        }
    }

    func cancel() { stateLock.withLock { waitState = nil } }
}

private enum WaiterState {
    case fallback(deadline: Date)
    case vad(deadline: Date, heardSpeech: Bool, quietSince: Double?)
}
