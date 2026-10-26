import Foundation

enum ActivityKind: String, Codable, Sendable {
    case cacheScan
    case gracefulQuit
    case cacheCleanup, fileScan, fileCleanup, smartBoost, developerStop
}

enum ActivityStatus: String, Codable, Sendable {
    case completed
    case partial
    case requested
    case notAccepted
    case cancelled, failed
}

/// A compact local history record. It deliberately has no app-name or path field.
struct ActivityRecord: Identifiable, Codable, Sendable {
    var id: UUID
    var date: Date
    var kind: ActivityKind
    var status: ActivityStatus
    var count: Int
    var estimatedBytes: UInt64?
    var availableStorageDelta: Int64? = nil

    var safeSummary: String {
        switch (kind, status) {
        case (.cacheScan, .completed): "Cache scan completed"
        case (.cacheScan, .partial): "Cache scan completed with skipped items"
        case (.gracefulQuit, .requested): "Graceful quit request sent"
        case (.gracefulQuit, .notAccepted): "Graceful quit request was not accepted"
        default: "Activity recorded"
        }
    }
}

/// Persists only aggregate activity metadata in local UserDefaults, retaining the newest records.
final class ActivityStore: @unchecked Sendable {
    static let defaultRetentionLimit = 100

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let storageKey: String
    private let retentionLimit: Int

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "MacPulse.activityHistory",
        retentionLimit: Int = ActivityStore.defaultRetentionLimit
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.retentionLimit = max(1, retentionLimit)
    }

    var records: [ActivityRecord] {
        lock.withLock { loadRecords() }
    }

    @discardableResult
    func recordCacheScan(
        folderCount: Int, estimatedBytes: UInt64, isComplete: Bool,
        date: Date = .now
    ) -> ActivityRecord {
        append(
            ActivityRecord(
                id: UUID(), date: date, kind: .cacheScan,
                status: isComplete ? .completed : .partial,
                count: max(0, folderCount), estimatedBytes: estimatedBytes))
    }

    @discardableResult
    func recordGracefulQuit(requestAccepted: Bool, date: Date = .now) -> ActivityRecord {
        append(
            ActivityRecord(
                id: UUID(), date: date, kind: .gracefulQuit,
                status: requestAccepted ? .requested : .notAccepted,
                count: 1, estimatedBytes: nil))
    }

    func clearHistory() {
        lock.withLock { defaults.removeObject(forKey: storageKey) }
    }

    @discardableResult
    func recordOperation(
        kind: ActivityKind, status: ActivityStatus, count: Int,
        estimatedBytes: UInt64? = nil, availableStorageDelta: Int64? = nil
    ) -> ActivityRecord {
        append(
            ActivityRecord(
                id: UUID(), date: .now, kind: kind, status: status,
                count: max(0, count), estimatedBytes: estimatedBytes,
                availableStorageDelta: availableStorageDelta))
    }

    private func append(_ record: ActivityRecord) -> ActivityRecord {
        lock.withLock {
            let updated = ([record] + loadRecords()).prefix(retentionLimit)
            guard let data = try? JSONEncoder().encode(Array(updated)) else { return record }
            defaults.set(data, forKey: storageKey)
            return record
        }
    }

    private func loadRecords() -> [ActivityRecord] {
        guard let data = defaults.data(forKey: storageKey),
            let records = try? JSONDecoder().decode([ActivityRecord].self, from: data)
        else {
            return []
        }
        return Array(records.prefix(retentionLimit))
    }
}
