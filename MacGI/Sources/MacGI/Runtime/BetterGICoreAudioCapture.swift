import AudioToolbox
import CoreMedia
import Foundation
import ScreenCaptureKit

protocol BGIAudioSampleProvider: AnyObject {
    func startCapture() throws
    func stopCapture()
    func readSamples() -> [Float]
    var isCapturing: Bool { get }
}

enum BetterGICoreAudioCaptureError: LocalizedError {
    case processNotFound(pid_t)
    case displayNotFound
    case startTimedOut
    case startProducedNoResult

    var errorDescription: String? {
        switch self {
        case let .processNotFound(pid): "找不到用于音频捕获的游戏进程 PID \(pid)"
        case .displayNotFound: "ScreenCaptureKit 未返回可用显示器"
        case .startTimedOut: "ScreenCaptureKit 音频捕获启动超时"
        case .startProducedNoResult: "ScreenCaptureKit 音频捕获未返回结果"
        }
    }
}

/// Platform-only process audio source for the C# BetterGI Core. It performs no VAD or dialogue logic.
@available(macOS 13.0, *)
final class BGIScreenCaptureKitAudioCapture: NSObject, BGIAudioSampleProvider, SCStreamOutput, @unchecked Sendable {
    private final class StartTransfer: @unchecked Sendable {
        var result: Result<SCStream, Error>?
    }

    private let targetProcessID: pid_t
    private var stream: SCStream?
    private var sampleQueue: [Float] = []
    private let queueLock = NSLock()
    private(set) var isCapturing = false

    init(targetProcessID: pid_t) {
        self.targetProcessID = targetProcessID
    }

    func startCapture() throws {
        guard !isCapturing else { return }
        let transfer = StartTransfer()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [targetProcessID, weak self] in
            do {
                guard let self else { throw CancellationError() }
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                guard let application = content.applications.first(where: {
                    $0.processID == targetProcessID
                }) else {
                    throw BetterGICoreAudioCaptureError.processNotFound(targetProcessID)
                }
                guard let display = content.displays.first else {
                    throw BetterGICoreAudioCaptureError.displayNotFound
                }
                let filter = SCContentFilter(
                    display: display,
                    including: [application],
                    exceptingWindows: []
                )
                let configuration = SCStreamConfiguration()
                configuration.capturesAudio = true
                configuration.excludesCurrentProcessAudio = true
                configuration.sampleRate = 16_000
                configuration.channelCount = 1
                configuration.width = 2
                configuration.height = 2
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
                try stream.addStreamOutput(
                    self,
                    type: .audio,
                    sampleHandlerQueue: DispatchQueue(
                        label: "bettergi.core.audio.samples", qos: .userInitiated
                    )
                )
                try await stream.startCapture()
                transfer.result = .success(stream)
            } catch {
                transfer.result = .failure(error)
            }
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 15) == .success else {
            throw BetterGICoreAudioCaptureError.startTimedOut
        }
        guard let result = transfer.result else {
            throw BetterGICoreAudioCaptureError.startProducedNoResult
        }
        stream = try result.get()
        isCapturing = true
    }

    func stopCapture() {
        if let stream {
            Task { try? await stream.stopCapture() }
        }
        stream = nil
        isCapturing = false
        queueLock.withLock { sampleQueue.removeAll() }
    }

    func readSamples() -> [Float] {
        queueLock.withLock {
            let result = sampleQueue
            sampleQueue.removeAll()
            return result
        }
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              sampleBuffer.isValid,
              let formatDescription = sampleBuffer.formatDescription,
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
              streamDescription.pointee.mBitsPerChannel == 32,
              streamDescription.pointee.mChannelsPerFrame == 1,
              streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0
        else { return }

        var bufferListSize = 0
        var retainedBlockBuffer: CMBlockBuffer?
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &retainedBlockBuffer
        )
        guard sizeStatus == noErr, bufferListSize >= MemoryLayout<AudioBufferList>.size else { return }
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        let audioBufferList = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        let listStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        )
        guard listStatus == noErr else { return }

        var captured: [Float] = []
        for buffer in UnsafeMutableAudioBufferListPointer(audioBufferList) {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
            captured.append(contentsOf: UnsafeBufferPointer(
                start: data.assumingMemoryBound(to: Float.self), count: count
            ))
        }
        if !captured.isEmpty {
            queueLock.withLock { sampleQueue.append(contentsOf: captured) }
        }
    }
}
