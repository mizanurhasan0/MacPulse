import Foundation

struct CachedScanFingerprint: Sendable {
    let stamp: FileStamp
    var sample: String?
    var fullHash: String?
}

/// Memory only: never stores file paths or content fingerprints on disk. Snapshots
/// keep a scan's cache hits stable while concurrent workers populate the next cache.
actor ScanFingerprintCache {
    private struct Entry {
        var fingerprint: CachedScanFingerprint
        var lastUsed: UInt64
        var updatedAt: ContinuousClock.Instant
    }
    private var entries: [String: Entry] = [:]
    private var accessCounter: UInt64 = 0
    private let capacity: Int
    private let lifetime: Duration

    init(capacity: Int = 16_384, lifetime: Duration = .seconds(600)) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
    }

    func snapshot(for root: URL) -> [String: CachedScanFingerprint] {
        let now = ContinuousClock().now
        entries = entries.filter { $0.value.updatedAt.duration(to: now) < lifetime }
        let prefix = FilePathPolicy.normalized(root).path + "/"
        var result: [String: CachedScanFingerprint] = [:]
        for path in Array(entries.keys) where path.hasPrefix(prefix) {
            accessCounter &+= 1
            entries[path]?.lastUsed = accessCounter
            result[path] = entries[path]?.fingerprint
        }
        return result
    }

    func store(_ file: ScannedFile, sample: String? = nil, fullHash: String? = nil) {
        let path = FilePathPolicy.normalized(file.url).path
        var fingerprint = entries[path]?.fingerprint
        if fingerprint?.stamp != file.stamp {
            fingerprint = CachedScanFingerprint(stamp: file.stamp, sample: nil, fullHash: nil)
        }
        guard var fingerprint else { return }
        if let sample { fingerprint.sample = sample }
        if let fullHash { fingerprint.fullHash = fullHash }
        accessCounter &+= 1
        entries[path] = Entry(fingerprint: fingerprint, lastUsed: accessCounter, updatedAt: ContinuousClock().now)
        if entries.count > capacity {
            // Evict in batches to avoid a complete sort for each newly seen file.
            let count = max(1, capacity / 4)
            let victims = entries.sorted { $0.value.lastUsed < $1.value.lastUsed }.prefix(count).map(\.key)
            for path in victims { entries.removeValue(forKey: path) }
        }
    }

    func clear() { entries.removeAll(keepingCapacity: false) }
    var count: Int { entries.count }
}
