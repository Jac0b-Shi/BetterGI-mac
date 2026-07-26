import CoreGraphics
import Foundation
@testable import MacGI
import Testing

@Suite("LatestFrameStore")
struct LatestFrameStoreTests {

    private func makeFrame(windowID: CGWindowID = 1,
                           timestamp: Date = Date(),
                           frameIndex: UInt64 = 42) -> CaptureImageFrame {
        let meta = CapturedFrame(
            frameIndex: frameIndex, timestamp: timestamp,
            width: 1920, height: 1080, scaleFactor: 1,
            pixelFormat: 0x42475241, bytesPerRow: 1920 * 4,
            sourceWindow: WindowInfo(id: windowID, ownerPID: 100, ownerName: "Test",
                                     title: "Test", frame: .zero, layer: 0,
                                     isOnScreen: true, scaleFactor: 1)
        )
        let cg = CGContext(data: nil,
                                width: 1920, height: 1080,
                                bitsPerComponent: 8, bytesPerRow: 1920 * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return CaptureImageFrame(metadata: meta, cgImage: cg, backendName: "Test")
    }

    // MARK: - Basic

    @Test("Empty store → missing error")
    func emptyStoreThrowsMissing() {
        let store = LatestFrameStore()
        #expect(throws: LatestFrameStoreError.missingLatestFrame) {
            try store.requireFreshSnapshot(forWindowID: 1)
        }
    }

    @Test("Fresh frame → success with correct metadata")
    func freshFrameReturnsSnapshot() throws {
        let store = LatestFrameStore()
        store.now = { Date(timeIntervalSinceReferenceDate: 100) }
        let frame = makeFrame(windowID: 1, timestamp: store.now())
        store.update(frame)

        let snap = try store.requireFreshSnapshot(forWindowID: 1)
        #expect(snap.metadata.frameIndex == 42)
        #expect(snap.metadata.sourceWindow.id == 1)
        #expect(snap.metadata.width == 1920)
        #expect(snap.metadata.height == 1080)
    }

    // MARK: - Staleness

    @Test("Stale frame → stale error")
    func staleFrameThrows() {
        let store = LatestFrameStore()
        store.staleThreshold = 0.5
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        store.now = { t0 }
        store.update(makeFrame(windowID: 1, timestamp: t0))

        // Advance clock past threshold
        store.now = { Date(timeIntervalSinceReferenceDate: 100.6) }
        do {
            _ = try store.requireFreshSnapshot(forWindowID: 1)
            Issue.record("Expected stale error, got success")
        } catch let error as LatestFrameStoreError {
            if case .staleLatestFrame(let age) = error {
                #expect(abs(age - 0.6) < 0.01)
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("Frame within threshold → success")
    func frameWithinThresholdSucceeds() throws {
        let store = LatestFrameStore()
        store.staleThreshold = 0.5
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        store.now = { t0 }
        store.update(makeFrame(windowID: 1, timestamp: t0))

        store.now = { Date(timeIntervalSinceReferenceDate: 100.3) }
        _ = try store.requireFreshSnapshot(forWindowID: 1)
    }

    // MARK: - Window mismatch

    @Test("Window mismatch → mismatch error")
    func windowMismatchThrows() {
        let store = LatestFrameStore()
        store.now = { Date(timeIntervalSinceReferenceDate: 100) }
        store.update(makeFrame(windowID: 5, timestamp: store.now()))

        #expect(throws: LatestFrameStoreError.latestFrameWindowMismatch(requested: 3, stored: 5)) {
            try store.requireFreshSnapshot(forWindowID: 3)
        }
    }

    // MARK: - Update overwrites

    @Test("Update overwrites old frame")
    func updateOverwrites() throws {
        let store = LatestFrameStore()
        store.now = { Date(timeIntervalSinceReferenceDate: 100) }
        store.update(makeFrame(windowID: 1, timestamp: store.now(), frameIndex: 1))
        store.update(makeFrame(windowID: 1, timestamp: store.now(), frameIndex: 2))

        let snap = try store.requireFreshSnapshot(forWindowID: 1)
        #expect(snap.metadata.frameIndex == 2)
    }

    // MARK: - Concurrency

    @Test("Concurrent read/write does not crash", arguments: [100, 500])
    func concurrentAccess(iterations: Int) {
        let store = LatestFrameStore()
        store.now = { Date() }
        store.update(makeFrame(windowID: 1, timestamp: store.now()))

        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 3 == 0 {
                store.update(makeFrame(windowID: 1, timestamp: store.now(), frameIndex: UInt64(i)))
            } else {
                _ = store.snapshotAny()
            }
        }
        // If we get here without crashing, the test passes.
    }

    // MARK: - Reset

    @Test("Reset clears stored frame")
    func resetClears() {
        let store = LatestFrameStore()
        store.now = { Date(timeIntervalSinceReferenceDate: 100) }
        store.update(makeFrame(windowID: 1, timestamp: store.now()))
        #expect(store.snapshotAny() != nil)
        store.reset()
        #expect(store.snapshotAny() == nil)
    }

    // MARK: - No-MainActor deadlock

    @MainActor
    @Test("Snapshot from MainActor does not deadlock")
    func mainActorNoDeadlock() throws {
        let store = LatestFrameStore()
        store.now = { Date() }
        store.update(makeFrame(windowID: 1, timestamp: store.now()))

        // Must return immediately — no semaphore, no nested Task { @MainActor }
        let timeout = Date().addingTimeInterval(1)
        while Date() < timeout {
            if (try? store.requireFreshSnapshot(forWindowID: 1)) != nil {
                return
            }
        }
        Issue.record("Snapshot from MainActor timed out — possible deadlock")
    }

    @MainActor
    @Test("Stale snapshot from MainActor throws immediately")
    func mainActorStaleThrowsImmediately() {
        let store = LatestFrameStore()
        store.staleThreshold = 0.5
        let t0 = Date(timeIntervalSinceReferenceDate: 100)
        store.now = { t0 }
        store.update(makeFrame(windowID: 1, timestamp: t0))
        store.now = { Date(timeIntervalSinceReferenceDate: 100.6) }

        do {
            _ = try store.requireFreshSnapshot(forWindowID: 1)
            Issue.record("Expected stale error, got success")
        } catch let error as LatestFrameStoreError {
            switch error {
            case .staleLatestFrame:
                break // expected
            default:
                Issue.record("Unexpected error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}
