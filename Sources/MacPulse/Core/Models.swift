import Foundation

enum ThermalCondition: Sendable {
    case normal, fair, serious, critical, unknown
}

struct CleanerSnapshot: Sendable {
    var timestamp: Date
    var cpuPercent: Double?
    var totalStorageBytes: UInt64
    var availableStorageBytes: UInt64
    var totalMemoryBytes: UInt64
    var thermalCondition: ThermalCondition

    var usedStorageBytes: UInt64 {
        totalStorageBytes > availableStorageBytes ? totalStorageBytes - availableStorageBytes : 0
    }
    var storageUsedFraction: Double {
        totalStorageBytes > 0 ? Double(usedStorageBytes) / Double(totalStorageBytes) : 0
    }
}

struct CleanupEntry: Identifiable, Sendable {
    enum State: Sendable, Equatable { case pending, cleaning, removed, retained }

    var id: String { url.path }
    var url: URL
    var category: String
    var estimatedBytes: UInt64
    var state: State = .pending
    var isSelected: Bool = true
    var allowedRootPath: String
    var device: UInt64
    var inode: UInt64
    var modificationSeconds: Int64
    var ownerBundleIdentifier: String?
}

struct CleanupLogLine: Identifiable, Sendable {
    var id = UUID()
    var text: String
    var isWarning = false
}
