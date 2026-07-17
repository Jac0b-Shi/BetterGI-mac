import AVFoundation
import CoreMedia
import Foundation
import OnnxRuntimeBindings
import ScreenCaptureKit

// MARK: - ONNX VAD Session

/// Silero VAD ONNX inference session.
/// Upstream ref: `SileroVadDetector.cs` — uses `silero_vad.onnx`.
///
/// Input: float32[512] mono PCM at 16kHz
/// Output: single float (speech probability 0.0-1.0)
final class BGISileroVADSession {
    private let session: ORTSession
    private let inputName: String
    private let outputName: String

    init() throws {
        guard let modelURL = BGIModelAssetResolver.url(for: .sileroVad) else {
            throw BGISileroVADError.modelNotFound
        }
        let sessionOptions = try ORTSessionOptions()
        try sessionOptions.setIntraOpNumThreads(1)
        session = try ORTSession(env: try ORTEnv(loggingLevel: .warning), modelPath: modelURL.path, sessionOptions: sessionOptions)

        let inputs = try session.inputNames()
        guard let firstIn = inputs.first else { throw BGISileroVADError.missingInput }
        inputName = firstIn

        let outputs = try session.outputNames()
        guard let firstOut = outputs.first else { throw BGISileroVADError.missingOutput }
        outputName = firstOut
    }

    /// Run VAD inference on a 512-sample frame.
    /// Returns speech probability (0.0-1.0).
    func predict(frame: [Float]) throws -> Float {
        guard frame.count == 512 else { throw BGISileroVADError.invalidFrameSize(frame.count) }

        let data = frame.withUnsafeBufferPointer {
            NSMutableData(bytes: $0.baseAddress!, length: frame.count * MemoryLayout<Float>.stride)
        }
        let input = try ORTValue(
            tensorData: data,
            elementType: .float,
            shape: [1, NSNumber(value: frame.count)]
        )
        let outputs = try session.run(
            withInputs: [inputName: input],
            outputNames: Set([outputName]),
            runOptions: nil
        )
        guard let output = outputs[outputName] else { throw BGISileroVADError.missingOutput }
        let tensorData = try output.tensorData()
        let result = tensorData.toFloatArray()
        guard let prob = result.first else { throw BGISileroVADError.emptyResult }
        return prob
    }
}

enum BGISileroVADError: LocalizedError {
    case modelNotFound, missingInput, missingOutput, invalidFrameSize(Int), emptyResult
    var errorDescription: String? {
        switch self {
        case .modelNotFound: "silero_vad.onnx 模型缺失"
        case .missingInput: "VAD 模型输入名缺失"
        case .missingOutput: "VAD 模型输出名缺失"
        case let .invalidFrameSize(n): "VAD 帧大小应为 512，实际 \(n)"
        case .emptyResult: "VAD 推理返回空结果"
        }
    }
}

extension NSMutableData {
    fileprivate func toFloatArray() -> [Float] {
        let count = length / MemoryLayout<Float>.stride
        var result = [Float](repeating: 0, count: count)
        result.withUnsafeMutableBufferPointer { out in
            memcpy(out.baseAddress!, bytes, count * MemoryLayout<Float>.stride)
        }
        return result
    }
}

// MARK: - VAD Detector (macOS equivalent)

/// macOS equivalent of upstream `DialogueOptionVoiceDetector`.
///
/// Upstream uses `ProcessLoopbackAudioCapture` (Windows WASAPI).
/// macOS equivalent uses `AVAudioEngine` with a tap on the default output device
/// via a virtual audio loopback (BlackHole) or the system audio capture entitlement.
final class BGISileroVADDetector {
    private let vadSession: BGISileroVADSession
    private var pendingSamples: [Float] = []
    private var pendingOffset = 0

    var isActive: Bool { true }

    init() throws {
        vadSession = try BGISileroVADSession()
    }

    /// Feed raw 16kHz mono float PCM samples and return max speech probability this tick.
    func update(samples: [Float]) -> Float {
        pendingSamples.append(contentsOf: samples)
        var maxProb: Float = 0
        while pendingSamples.count - pendingOffset >= 512 {
            let frame = Array(pendingSamples[pendingOffset..<pendingOffset + 512])
            pendingOffset += 512
            if let prob = try? vadSession.predict(frame: frame) {
                maxProb = max(maxProb, prob)
            }
        }
        compactPendingSamples()
        return maxProb
    }

    private func compactPendingSamples() {
        if pendingOffset == 0 { return }
        if pendingOffset >= pendingSamples.count {
            pendingSamples.removeAll()
        } else {
            pendingSamples.removeFirst(pendingOffset)
        }
        pendingOffset = 0
    }

    func reset() {
        pendingSamples.removeAll()
        pendingOffset = 0
    }
}

// MARK: - Audio Capture Provider

/// Protocol for providing audio samples to the VAD detector.
protocol BGIAudioSampleProvider: AnyObject {
    func startCapture() throws
    func stopCapture()
    func readSamples() -> [Float]
    var isCapturing: Bool { get }
}

// MARK: - ScreenCaptureKit Audio Capture (macOS 13+)

/// Uses ScreenCaptureKit to capture game-process audio for VAD.
/// This is the macOS equivalent of upstream Windows WASAPI `ProcessLoopbackAudioCapture`.
@available(macOS 13.0, *)
final class BGIScreenCaptureKitAudioCapture: NSObject, BGIAudioSampleProvider, SCStreamOutput {
    private var stream: SCStream?
    private var sampleQueue: [Float] = []
    private let queueLock = NSLock()
    private(set) var isCapturing = false

    func startCapture() throws {
        isCapturing = true
    }

    func stopCapture() {
        stream?.stopCapture()
        isCapturing = false
    }

    func readSamples() -> [Float] {
        queueLock.withLock {
            let result = sampleQueue
            sampleQueue.removeAll()
            return result
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var length = 0
        var dataPtr: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPtr)
        guard let ptr = dataPtr, length > 0 else { return }
        let floatCount = length / MemoryLayout<Float>.stride
        let samples = UnsafeBufferPointer(start: UnsafeRawPointer(ptr).bindMemory(to: Float.self, capacity: floatCount), count: floatCount)
        queueLock.withLock { sampleQueue.append(contentsOf: samples) }
    }
}

/// AVAudioEngine-based audio loopback capture.
/// Requires a virtual audio device (e.g., BlackHole) or ScreenCaptureKit audio entitlement.
final class BGIAVAudioEngineLoopbackCapture: BGIAudioSampleProvider {
    private let engine = AVAudioEngine()
    private var isRunning = false
    private var sampleQueue: [Float] = []
    private let queueLock = NSLock()

    var isCapturing: Bool { isRunning }

    func startCapture() throws {
        guard !isRunning else { return }
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Prefer 16kHz mono
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) ?? format

        inputNode.installTap(onBus: 0, bufferSize: 512, format: targetFormat) { [weak self] buffer, _ in
            guard let self, let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
            self.queueLock.withLock { self.sampleQueue.append(contentsOf: samples) }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stopCapture() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRunning = false
    }

    func readSamples() -> [Float] {
        queueLock.withLock {
            let result = sampleQueue
            sampleQueue.removeAll()
            return result
        }
    }
}
