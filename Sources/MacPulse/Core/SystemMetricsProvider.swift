import Foundation
import Darwin
import Darwin.Mach
import AppKit
import IOKit
import IOKit.pwr_mgt
import Darwin.libproc
import Dispatch

@MainActor final class LiveSystemMetricsProvider: SystemMetricsProvider {
    private var previousCPUTicks: [UInt32]?
    private var processCPUSampler = ProcessCPUSampler()

    func snapshot() async throws -> PerformanceSnapshot {
        let cpu = readCPU()
        let memory = readMemory()
        let storage = readStorage()
        let thermal = readThermal()
        let processes = readProcesses()
        return PerformanceSnapshot(timestamp: Date(), cpu: cpu, memory: memory,
                                   storage: storage, thermal: thermal, processes: processes)
    }

    private func readCPU() -> CPUReading {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return CPUReading(total: 0, user: 0, system: 0, idle: 0, isAvailable: false) }
        let ticks: [UInt32] = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { previousCPUTicks = ticks }
        guard let previousCPUTicks else { return CPUReading(total: 0, user: 0, system: 0, idle: 0, isAvailable: false) }
        return CPUReading.interval(current: ticks, previous: previousCPUTicks)
            ?? CPUReading(total: 0, user: 0, system: 0, idle: 0, isAvailable: false)
    }

    private func readMemory() -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let physical = ProcessInfo.processInfo.physicalMemory
        let swapUsed = readSwapUsedBytes()
        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return MemoryReading(physicalBytes: physical, appBytes: 0, wiredBytes: 0,
                                 compressedBytes: 0, swapUsedBytes: swapUsed, pressure: .unavailable)
        }
        let page = UInt64(pageSize)
        guard result == KERN_SUCCESS else {
            return MemoryReading(physicalBytes: physical, appBytes: 0, wiredBytes: 0,
                                 compressedBytes: 0, swapUsedBytes: swapUsed, pressure: .unavailable)
        }
        let appPages = UInt64(stats.internal_page_count)
        let wiredPages = UInt64(stats.wire_count)
        let compressedPages = UInt64(stats.compressor_page_count)
        let availableFraction = stats.estimatedAvailableFraction(physicalPages: physical / page)
        let pressure = stats.estimatedPressure(physicalPages: physical / page)
        return MemoryReading(physicalBytes: physical, appBytes: appPages * page,
                             wiredBytes: wiredPages * page, compressedBytes: compressedPages * page,
                             swapUsedBytes: swapUsed, pressure: pressure,
                             estimatedAvailableFraction: availableFraction)
    }

    private func readSwapUsedBytes() -> UInt64? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
        }
        guard status == 0, size == MemoryLayout<xsw_usage>.size else { return nil }
        return usage.xsu_used
    }

    private func readStorage() -> StorageReading {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
            let importantAvailable = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
            let availableFallback = values.volumeAvailableCapacity.map { UInt64(max(0, $0)) }
            let available = importantAvailable ?? availableFallback ?? 0
            return StorageReading(totalBytes: total, availableBytes: min(total, available))
        } catch { return StorageReading(totalBytes: 0, availableBytes: 0) }
    }

    private func readThermal() -> ThermalReading {
        let state = ProcessInfo.processInfo.thermalState
        let health: HealthState = switch state {
        case .nominal: .healthy
        case .fair, .serious: .attention
        case .critical: .critical
        @unknown default: .unavailable
        }
        return ThermalReading(state: state, health: health)
    }

    private func readProcesses() -> [ProcessReading] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated && $0.processIdentifier > 0 }
        processCPUSampler.retain(pids: Set(apps.map(\.processIdentifier)))
        let now = DispatchTime.now().uptimeNanoseconds
        return apps
            .map { app in
                var usage = rusage_info_v4()
                // libproc declares this buffer through the opaque rusage_info_t pointer alias;
                // the API writes the requested versioned struct into caller-provided storage.
                let status = withUnsafeMutablePointer(to: &usage) { pointer in
                    pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(app.processIdentifier, RUSAGE_INFO_V4, $0)
                    }
                }
                let path = app.executableURL?.standardizedFileURL.path
                let cpu: Double?
                if status == 0 {
                    cpu = processCPUSampler.sample(pid: app.processIdentifier, executablePath: path,
                                                  processStartTime: usage.ri_proc_start_abstime,
                                                  userNanoseconds: usage.ri_user_time,
                                                  systemNanoseconds: usage.ri_system_time,
                                                  sampledAtNanoseconds: now)
                } else {
                    processCPUSampler.discard(pid: app.processIdentifier)
                    cpu = nil
                }
                return ProcessReading(pid: app.processIdentifier,
                                      name: app.localizedName ?? app.bundleIdentifier ?? "Unknown Application",
                                      bundleIdentifier: app.bundleIdentifier,
                                      memoryBytes: status == 0 ? usage.ri_phys_footprint : 0,
                                      cpuPercent: cpu,
                                      executablePath: path, launchDate: app.launchDate)
            }
            .sorted { $0.memoryBytes > $1.memoryBytes }
    }
}

private extension vm_statistics64_data_t {
    func estimatedAvailableFraction(physicalPages: UInt64) -> Double? {
        guard physicalPages > 0 else { return nil }
        let available = UInt64(free_count) + UInt64(inactive_count) + UInt64(speculative_count)
        return min(1, Double(available) / Double(physicalPages))
    }

    func estimatedPressure(physicalPages: UInt64) -> HealthState {
        guard let fraction = estimatedAvailableFraction(physicalPages: physicalPages) else { return .unavailable }
        // This is only a page-availability estimate, not macOS's memory pressure level.
        if fraction < 0.03 { return .critical }
        if fraction < 0.08 { return .attention }
        return .healthy
    }
}
