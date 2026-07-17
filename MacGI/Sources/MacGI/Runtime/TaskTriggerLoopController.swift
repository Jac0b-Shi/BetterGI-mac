import Foundation

struct TaskTriggerLoopStats: Equatable, Sendable {
    var intervalMs: Int
    var tickCount: UInt64
    var skippedTickCount: UInt32
    var lastTickCostMs: Double
}

/// Async counterpart to BetterGI `TaskTriggerDispatcher`'s timer loop.
///
/// BetterGI uses a `System.Timers.Timer` at roughly 50ms and skips work when
/// the previous tick still holds the dispatch lock. This controller keeps a
/// serial async loop and records schedule overruns as skipped ticks so the UI
/// can still expose the same pressure signal.
@MainActor
final class TaskTriggerLoopController {
    private var task: Task<Void, Never>?
    private(set) var stats = TaskTriggerLoopStats(
        intervalMs: 50,
        tickCount: 0,
        skippedTickCount: 0,
        lastTickCostMs: 0
    )

    var isRunning: Bool {
        task != nil
    }

    var onStatsChanged: ((TaskTriggerLoopStats) -> Void)?

    func start(intervalMs: Int = 50, tick: @escaping @MainActor () async -> Void) {
        stop()

        let safeIntervalMs = max(10, intervalMs)
        stats = TaskTriggerLoopStats(
            intervalMs: safeIntervalMs,
            tickCount: 0,
            skippedTickCount: 0,
            lastTickCostMs: 0
        )
        onStatsChanged?(stats)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let startedAt = Date()
                await tick()

                let elapsed = Date().timeIntervalSince(startedAt)
                stats.tickCount += 1
                stats.lastTickCostMs = elapsed * 1000

                let interval = Double(safeIntervalMs) / 1000
                if elapsed > interval {
                    let overrunIntervals = max(1, Int(elapsed / interval))
                    stats.skippedTickCount &+= UInt32(overrunIntervals)
                }
                onStatsChanged?(stats)

                let sleepSeconds = max(0, interval - elapsed)
                if sleepSeconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
