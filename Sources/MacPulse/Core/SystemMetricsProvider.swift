import Darwin
import Darwin.Mach
import Foundation

@MainActor final class LiveSystemMetricsProvider {
    private var previousCPUTicks: [UInt32]?

    func snapshot() -> CleanerSnapshot {
        let cpu = readCPU()
        let root = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? root.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        ])
        let total = UInt64(max(0, values?.volumeTotalCapacity ?? 0))
        let available = UInt64(max(0, values?.volumeAvailableCapacity ?? 0))
        let thermal: ThermalCondition = switch ProcessInfo.processInfo.thermalState {
        case .nominal: .normal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
        return CleanerSnapshot(
            timestamp: .now,
            cpuPercent: cpu,
            totalStorageBytes: total,
            availableStorageBytes: min(total, available),
            totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            thermalCondition: thermal)
    }

    private func readCPU() -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let ticks: [UInt32] = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousCPUTicks = ticks }
        guard let previousCPUTicks else { return nil }
        let delta = zip(ticks, previousCPUTicks).map { UInt64($0 &- $1) }
        let user = Double(delta[0])
        let system = Double(delta[1] + delta[3])
        let idle = Double(delta[2])
        let total = user + system + idle
        return total > 0 ? (user + system) / total * 100 : nil
    }
}
