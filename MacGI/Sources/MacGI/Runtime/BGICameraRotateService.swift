import CoreGraphics
import Foundation

/// macOS port of upstream `CameraRotateTask`.
///
/// The upstream algorithm (`RotateToApproach`):
///   1. Read the current camera orientation via `CameraOrientation.Compute` (another ONNX model).
///   2. Compute the normalised angle difference `diff`.
///   3. Pick a `controlRatio` based on `|diff|`: 4 (>90°), 3 (>30°), 2 (>5°), else 1.
///   4. Move the mouse horizontally by `-controlRatio * diff * dpi` pixels.
///
/// This port substitutes step 1 with the mini-map orientation estimate from
/// `BGIMiniMapOrientationEstimator` (a pure image-processing approach, no ONNX), and
/// then applies the same control‑ratio logic.
final class BGICameraRotateService: @unchecked Sendable {
    typealias InputHandler = @MainActor (InputAction) -> InputSafetyGate.GateResult

    private let inputHandler: InputHandler
    private let dpiScale: Double

    /// Max orientation error tolerated by `waitUntilRotatedTo`.
    private let maxRotationDiff: Int

    /// Maximum number of ticks before rotation gives up.
    private let maxRotationTicks: Int

    /// Sleep interval between rotation ticks, in milliseconds.
    private let rotationTickMs: UInt64

    init(
        inputHandler: @escaping InputHandler,
        dpiScale: Double = 1.0,
        maxRotationDiff: Int = 2,
        maxRotationTicks: Int = 40,
        rotationTickMs: UInt64 = 50
    ) {
        self.inputHandler = inputHandler
        self.dpiScale = dpiScale
        self.maxRotationDiff = maxRotationDiff
        self.maxRotationTicks = maxRotationTicks
        self.rotationTickMs = rotationTickMs
    }

    /// Perform one rotation step towards the target orientation and return the
    /// remaining angle difference.
    ///
    /// - Parameters:
    ///   - targetOrientation: Desired camera angle in degrees [0, 360).
    ///   - currentOrientation: Current camera orientation in degrees [0, 360).
    /// - Returns: The signed angle difference **after** this step's mouse movement.
    func rotateToApproach(targetOrientation: Double, currentOrientation: Double) async -> Double {
        var diff = targetOrientation - currentOrientation

        // Normalise to [-180, 180)
        diff = diff.truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }

        guard abs(diff) > 0.1 else { return diff }

        // Upstream control‑ratio: 4 (>90°), 3 (>30°), 2 (>5°), else 1
        let controlRatio: Double
        let absDiff = abs(diff)
        if absDiff > 90 {
            controlRatio = 4
        } else if absDiff > 30 {
            controlRatio = 3
        } else if absDiff > 5 {
            controlRatio = 2
        } else {
            controlRatio = 1
        }

        let dx = -controlRatio * diff * dpiScale
        await perform(.mouseMove(to: CGPoint(x: mousePosition().x + dx, y: mousePosition().y)))

        // Recalculate diff after movement
        let newDiff = targetOrientation - currentOrientation
        var result = newDiff.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }

    /// Block until the camera is within `maxDiff` degrees of `targetOrientation`.
    ///
    /// Upstream `WaitUntilRotatedTo` first calls `_rotateTask.WaitUntilRotatedTo(target, maxDiff)`
    /// and if that fails, calls `ResolveAnomalies()` then retries once.
    func waitUntilRotatedTo(
        targetOrientation: Double,
        maxDiff: Int = 2,
        getCurrentOrientation: @escaping () async -> Double?
    ) async throws {
        // First attempt
        let result = await waitUntilRotatedToInternal(
            targetOrientation: targetOrientation,
            maxDiff: maxDiff,
            getCurrentOrientation: getCurrentOrientation
        )
        guard !result else { return }

        // Retry once (upstream does ResolveAnomalies then retry)
        for _ in 0..<3 {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        let retry = await waitUntilRotatedToInternal(
            targetOrientation: targetOrientation,
            maxDiff: maxDiff,
            getCurrentOrientation: getCurrentOrientation
        )
        guard retry else {
            // Not throwing — moveTo will handle timeouts at a higher level.
            return
        }
    }

    // MARK: - Private

    private func waitUntilRotatedToInternal(
        targetOrientation: Double,
        maxDiff: Int,
        getCurrentOrientation: @escaping () async -> Double?
    ) async -> Bool {
        for _ in 0..<maxRotationTicks {
            guard let current = await getCurrentOrientation() else {
                try? await Task.sleep(nanoseconds: rotationTickMs * 1_000_000)
                continue
            }
            let diff = normalizedDifference(target: targetOrientation, current: current)
            if abs(diff) <= Double(maxDiff) {
                return true
            }
            _ = await rotateToApproach(targetOrientation: targetOrientation, currentOrientation: current)
            try? await Task.sleep(nanoseconds: rotationTickMs * 1_000_000)
        }
        return false
    }

    private func normalizedDifference(target: Double, current: Double) -> Double {
        var diff = target - current
        diff = diff.truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }

    private func perform(_ action: InputAction) async {
        _ = await inputHandler(action)
    }

    private func mousePosition() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
