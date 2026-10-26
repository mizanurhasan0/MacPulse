import Foundation

enum HealthState: String, Codable, Sendable {
    case healthy, attention, critical, unavailable
}

struct PerformanceSnapshot: Sendable {
    var timestamp: Date
    var cpu: CPUReading
    var memory: MemoryReading
    var storage: StorageReading
    var thermal: ThermalReading
    var processes: [ProcessReading]
}

struct CPUReading: Sendable {
    var total: Double
    var user: Double
    var system: Double
    var idle: Double
    var isAvailable: Bool

    static func interval(current: [UInt32], previous: [UInt32]) -> CPUReading? {
        guard current.count == 4, previous.count == 4 else { return nil }
        // CPU counters are unsigned and can wrap; use wrapping subtraction before widening.
        let delta = zip(current, previous).map { UInt64($0 &- $1) }
        let user = Double(delta[0])
        let system = Double(delta[1] + delta[3])
        let idle = Double(delta[2])
        let sum = user + system + idle
        guard sum > 0 else { return nil }
        return CPUReading(total: (user + system) / sum * 100,
                          user: user / sum * 100,
                          system: system / sum * 100,
                          idle: idle / sum * 100,
                          isAvailable: true)
    }
}

struct MemoryReading: Sendable {
    var physicalBytes: UInt64
    var appBytes: UInt64
    var wiredBytes: UInt64
    var compressedBytes: UInt64
    var swapUsedBytes: UInt64?
    var pressure: HealthState
    var estimatedAvailableFraction: Double? = nil
}

struct StorageReading: Sendable {
    var totalBytes: UInt64
    var availableBytes: UInt64
    var usedBytes: UInt64 { totalBytes > availableBytes ? totalBytes - availableBytes : 0 }
    var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

struct ThermalReading: Sendable {
    var state: ProcessInfo.ThermalState
    var health: HealthState
    /// No supported public macOS API supplies a CPU temperature on the current implementation.
    /// Keep this nil rather than inferring Celsius from thermal pressure.
    var temperatureCelsius: Double? = nil
}

struct ProcessReading: Identifiable, Sendable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var bundleIdentifier: String?
    var memoryBytes: UInt64
    var cpuPercent: Double?
    var executablePath: String? = nil
    var launchDate: Date? = nil
    var pidText: String { String(pid) }
    var cpuText: String { cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—" }
    var memoryFootprintText: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }
}

enum ProcessProtectionPolicy {
    private static let protectedBundleIDs: Set<String> = [
        "com.apple.loginwindow", "com.apple.WindowServer", "com.apple.dock",
        "com.apple.finder", "com.apple.UserNotificationCenter", "com.apple.securityd"
    ]

    static func isProtected(_ process: ProcessReading, ownBundleIdentifier: String?) -> Bool {
        guard process.pid > 1, let bundleID = process.bundleIdentifier else { return true }
        let path = process.executablePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let isSystemExecutable = path?.hasPrefix("/System/") == true
            || path?.hasPrefix("/usr/libexec/") == true
            || path?.hasPrefix("/sbin/") == true
        return bundleID == ownBundleIdentifier
            || bundleID.hasPrefix("com.apple.")
            || protectedBundleIDs.contains(bundleID)
            || isSystemExecutable
    }
}

enum FindingCategory: String, Sendable {
    case cpu, memory, storage, thermal, developer
}

enum FindingConfidence: String, Sendable {
    case low, medium, high
}

enum FindingRisk: String, Sendable {
    case low, reviewRequired, high
}

struct Finding: Identifiable, Sendable {
    var id: String
    var category: FindingCategory
    var severity: HealthState
    var title: String
    var detail: String
    var evidence: String
    var destination: String
    var possibleCauses: [String] = []
    var confidence: FindingConfidence = .medium
    var risk: FindingRisk = .low
    var timestamp: Date = .now
}

struct CleanupCandidate: Identifiable, Sendable {
    var id: URL { url }
    var url: URL
    var displayName: String
    var allocatedBytes: UInt64
    /// Compatibility alias used by existing presentation code. Scanner values are allocated-size estimates.
    var logicalBytes: UInt64 { allocatedBytes }
    var explanation: String
    var risk: String
    var isComplete: Bool = true
    var stamp: FileStamp? = nil
    var inventoryFingerprint: String? = nil
}

@MainActor protocol SystemMetricsProvider: Sendable {
    func snapshot() async throws -> PerformanceSnapshot
}

protocol DiagnosticRule: Sendable {
    func evaluate(_ snapshot: PerformanceSnapshot) -> Finding?
}
