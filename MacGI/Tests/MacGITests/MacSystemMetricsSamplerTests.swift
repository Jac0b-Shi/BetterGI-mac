import Darwin
import Foundation
@testable import MacGI
import Testing

@Suite("macOS system metrics")
struct MacSystemMetricsSamplerTests {
    @Test("Process memory uses physical footprint and retains VM diagnostics")
    func processMemoryAccounting() async {
        let sampler = MacSystemMetricsSampler()

        let snapshot = await sampler.sample(bgiProcessIDs: [getpid()])

        #expect((snapshot.bgiPhysicalFootprintBytes ?? 0) > 0)
        #expect((snapshot.bgiVirtualSizeBytes ?? 0) >= (snapshot.bgiPhysicalFootprintBytes ?? 0))
        if let memoryPercent = snapshot.systemMemoryPercent {
            #expect((0 ... 100).contains(memoryPercent))
        }
        if let gpuPercent = snapshot.gpuPercent {
            #expect((0 ... 100).contains(gpuPercent))
        }
    }

    @Test("Second sample produces bounded CPU utilization")
    func cpuSampling() async throws {
        let sampler = MacSystemMetricsSampler()
        _ = await sampler.sample(bgiProcessIDs: [getpid()])
        var snapshot = MacSystemMetricsSnapshot.empty
        for _ in 0..<5 where snapshot.systemCPUPercent == nil {
            try await Task.sleep(for: .milliseconds(50))
            snapshot = await sampler.sample(bgiProcessIDs: [getpid()])
        }

        #expect(snapshot.systemCPUPercent.map { (0 ... 100).contains($0) } == true)
        #expect(snapshot.bgiCPUPercent.map { (0 ... 100).contains($0) } == true)
    }
}
