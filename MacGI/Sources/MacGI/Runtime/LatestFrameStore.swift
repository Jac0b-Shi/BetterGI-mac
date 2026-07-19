import CoreGraphics
import Foundation

// MARK: - Errors

enum LatestFrameStoreError: LocalizedError, Equatable {
    case missingLatestFrame
    case staleLatestFrame(age: TimeInterval)
    case latestFrameWindowMismatch(requested: CGWindowID, stored: CGWindowID)

    var errorDescription: String? {
        switch self {
        case .missingLatestFrame:
            "No captured frame has been stored yet"
        case let .staleLatestFrame(age):
            "Latest frame is \(String(format: "%.0f", age * 1000))ms old; exceeds freshness threshold"
        case let .latestFrameWindowMismatch(requested, stored):
            "Latest frame was captured from window \(stored), but \(requested) was requested"
        }
    }
}

// MARK: - Store

/// Thread-safe store that holds the most recent captured game frame.
///
/// Fed continuously by the active platform capture provider.
/// and read synchronously from any thread, including BetterGI Core platform callbacks.
/// without blocking on `@MainActor` or a semaphore.
///
/// **Concurrency invariant**: all mutable state is accessed only inside `lock`.
/// Snapshots return a consistent copy of the current frame including metadata.
///
/// This eliminates the semaphore‑deadlock risk that the previous bridge
/// (`DispatchSemaphore` + `Task { @MainActor in ... }`) introduced.
final class LatestFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: CaptureImageFrame?

    /// Maximum age (in seconds) before a frame is considered stale.
    var staleThreshold: TimeInterval = 0.5

    /// Clock used for staleness checks.  Overridable for testing.
    var now: () -> Date = { Date() }

    // MARK: - Write

    /// Replace the stored frame with a fresh capture.
    func update(_ frame: CaptureImageFrame) {
        lock.withLock { storage = frame }
    }

    /// Remove all stored frames (e.g. on window change).
    func reset() {
        lock.withLock { storage = nil }
    }

    // MARK: - Read

    /// Return the latest frame, throwing if missing, stale, or from a
    /// different window.
    func requireFreshSnapshot(forWindowID windowID: CGWindowID) throws -> CaptureImageFrame {
        let current = now()
        return try lock.withLock {
            guard let frame = storage else {
                throw LatestFrameStoreError.missingLatestFrame
            }
            guard frame.metadata.sourceWindow.id == windowID else {
                throw LatestFrameStoreError.latestFrameWindowMismatch(
                    requested: windowID,
                    stored: frame.metadata.sourceWindow.id
                )
            }
            let age = current.timeIntervalSince(frame.metadata.timestamp)
            guard age < staleThreshold else {
                throw LatestFrameStoreError.staleLatestFrame(age: age)
            }
            return frame
        }
    }

    /// Return a snapshot without freshness or window checks (for internal use).
    func snapshotAny() -> CaptureImageFrame? {
        lock.withLock { storage }
    }

    /// Age of the latest frame, or `nil` if empty.
    var age: TimeInterval? {
        lock.withLock {
            guard let frame = storage else { return nil }
            return now().timeIntervalSince(frame.metadata.timestamp)
        }
    }

    /// Window ID of the latest frame, or `nil` if empty.
    var latestWindowID: CGWindowID? {
        lock.withLock { storage?.metadata.sourceWindow.id }
    }
}

// MARK: - Lock helper

private extension NSLock {
    func withLock<T>(_ block: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try block()
    }
}
