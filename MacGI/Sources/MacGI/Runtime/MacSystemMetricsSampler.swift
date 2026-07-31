import Darwin
import Foundation
import IOKit

struct MacSystemMetricsSnapshot: Sendable, Equatable {
    let systemCPUPercent: Double?
    let gpuPercent: Double?
    let systemMemoryPercent: Double?
    let bgiCPUPercent: Double?
    // macOS 的 phys_footprint 才用于展示实际内存压力；virtual_size 仅供诊断，绝不能与前者相加。
    let bgiPhysicalFootprintBytes: UInt64?
    let bgiVirtualSizeBytes: UInt64?

    static let empty = MacSystemMetricsSnapshot(
        systemCPUPercent: nil,
        gpuPercent: nil,
        systemMemoryPercent: nil,
        bgiCPUPercent: nil,
        bgiPhysicalFootprintBytes: nil,
        bgiVirtualSizeBytes: nil)
}

actor MacSystemMetricsSampler {
    private struct ProcessUsage {
        let physicalFootprintBytes: UInt64
        let virtualSizeBytes: UInt64
        let cpuTimeNanoseconds: UInt64
    }

    private struct CPUTicks {
        let active: UInt64
        let total: UInt64
    }

    private var previousProcessCPUTime: [pid_t: UInt64] = [:]
    private var previousProcessSampleUptime: TimeInterval?
    private var previousSystemCPUTicks: CPUTicks?
    private var smoothedBGICPUPercent: Double?
    private var smoothedGPUPercent: Double?

    func sample(bgiProcessIDs: [pid_t]) -> MacSystemMetricsSnapshot {
        let processIDs = Set(bgiProcessIDs.filter { $0 > 0 })
        let processUsages = processIDs.reduce(into: [pid_t: ProcessUsage]()) { result, pid in
            if let usage = Self.processUsage(pid: pid) {
                result[pid] = usage
            }
        }

        let footprint = processUsages.isEmpty
            ? nil
            : processUsages.values.reduce(UInt64(0)) {
                $0 &+ $1.physicalFootprintBytes
            }
        let virtualSize = processUsages.isEmpty
            ? nil
            : processUsages.values.reduce(UInt64(0)) {
                $0 &+ $1.virtualSizeBytes
            }
        let bgiCPUPercent = sampleBGICPU(
            usages: processUsages,
            uptime: ProcessInfo.processInfo.systemUptime)
        let systemCPUPercent = sampleSystemCPU()
        let gpuPercent = Self.gpuUtilizationPercent().map {
            smoothedGPUPercent = Self.smooth(smoothedGPUPercent, $0)
            return smoothedGPUPercent!
        }

        return MacSystemMetricsSnapshot(
            systemCPUPercent: systemCPUPercent,
            gpuPercent: gpuPercent,
            systemMemoryPercent: Self.systemMemoryUsagePercent(),
            bgiCPUPercent: bgiCPUPercent,
            bgiPhysicalFootprintBytes: footprint,
            bgiVirtualSizeBytes: virtualSize)
    }

    private func sampleBGICPU(
        usages: [pid_t: ProcessUsage],
        uptime: TimeInterval
    ) -> Double? {
        defer {
            previousProcessCPUTime = usages.mapValues(\.cpuTimeNanoseconds)
            previousProcessSampleUptime = uptime
        }
        guard let previousUptime = previousProcessSampleUptime else { return nil }
        let elapsed = uptime - previousUptime
        guard elapsed > 0 else { return nil }

        let cpuDelta = usages.reduce(UInt64(0)) { total, entry in
            guard let previous = previousProcessCPUTime[entry.key],
                  entry.value.cpuTimeNanoseconds >= previous else {
                return total
            }
            return total &+ (entry.value.cpuTimeNanoseconds - previous)
        }
        let processorCount = max(1, ProcessInfo.processInfo.processorCount)
        let percent = Double(cpuDelta) / 1_000_000_000
            / elapsed / Double(processorCount) * 100
        let bounded = min(100, max(0, percent))
        smoothedBGICPUPercent = Self.smooth(smoothedBGICPUPercent, bounded)
        return smoothedBGICPUPercent
    }

    private func sampleSystemCPU() -> Double? {
        guard let current = Self.systemCPUTicks() else { return nil }
        defer { previousSystemCPUTicks = current }
        let lifetimeAverage = current.total > 0
            ? Double(current.active) / Double(current.total) * 100
            : nil
        guard let previous = previousSystemCPUTicks else {
            return lifetimeAverage
        }
        guard current.total >= previous.total,
              current.active >= previous.active else { return lifetimeAverage }
        let totalDelta = current.total - previous.total
        guard totalDelta > 0 else { return lifetimeAverage }
        return min(100, max(0, Double(current.active - previous.active)
            / Double(totalDelta) * 100))
    }

    private static func processUsage(pid: pid_t) -> ProcessUsage? {
        var usage = rusage_info_v4()
        let usageResult = withUnsafeMutablePointer(to: &usage) { usagePointer in
            let buffer = UnsafeMutableRawPointer(usagePointer)
                .assumingMemoryBound(to: rusage_info_t?.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_V4, buffer)
        }
        guard usageResult == 0 else { return nil }

        var taskInfo = proc_taskinfo()
        let expectedSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let taskInfoSize = withUnsafeMutablePointer(to: &taskInfo) {
            proc_pidinfo(pid, PROC_PIDTASKINFO, 0, $0, expectedSize)
        }
        guard taskInfoSize == expectedSize else { return nil }

        return ProcessUsage(
            physicalFootprintBytes: usage.ri_phys_footprint,
            virtualSizeBytes: taskInfo.pti_virtual_size,
            cpuTimeNanoseconds: usage.ri_user_time &+ usage.ri_system_time)
    }

    private static func systemCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size
                / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(
                    mach_host_self(),
                    HOST_CPU_LOAD_INFO,
                    $0,
                    &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(active: user &+ system &+ nice, total: user &+ system &+ nice &+ idle)
    }

    private static func systemMemoryUsagePercent() -> Double? {
        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size
                / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return nil }
        var hostPageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &hostPageSize) == KERN_SUCCESS else {
            return nil
        }
        let pageSize = UInt64(hostPageSize)
        let reclaimableBytes = (UInt64(info.free_count) + UInt64(info.speculative_count))
            &* pageSize
        let usedBytes = totalBytes > reclaimableBytes ? totalBytes - reclaimableBytes : 0
        return min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
    }

    private static func gpuUtilizationPercent() -> Double? {
        guard let matching = IOServiceMatching("AGXAccelerator") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            matching,
            &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var utilization: Double?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let property = IORegistryEntryCreateCFProperty(
                service,
                "PerformanceStatistics" as CFString,
                kCFAllocatorDefault,
                0)?.takeRetainedValue(),
               let statistics = property as? [String: Any] {
                let keys = [
                    "Device Utilization %",
                    "Renderer Utilization %",
                    "Tiler Utilization %",
                ]
                for key in keys {
                    if let number = statistics[key] as? NSNumber {
                        utilization = max(utilization ?? 0, number.doubleValue)
                    }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return utilization.map { min(100, max(0, $0)) }
    }

    private static func smooth(_ current: Double?, _ newValue: Double) -> Double {
        current.map { $0 * 0.7 + newValue * 0.3 } ?? newValue
    }
}
