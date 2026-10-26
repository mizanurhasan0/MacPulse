import Darwin
import Foundation
import XCTest

@testable import MacPulse

@MainActor final class ParallelScanTests: XCTestCase {
    func testBoundedWorkersPreserveOrderingAndRespectLimit() async throws {
        let probe = WorkerProbe()
        let output = try await BoundedScanWork.map(Array(0..<40), limit: { 3 }) { value in
            await probe.enter()
            try await Task.sleep(for: .milliseconds(value.isMultiple(of: 2) ? 3 : 1))
            await probe.leave()
            return value * 2
        }
        XCTAssertEqual(output, Array(0..<40).map { $0 * 2 })
        let peak = await probe.peak
        let active = await probe.active
        XCTAssertEqual(peak, 3)
        XCTAssertEqual(active, 0)
    }

    func testCancellationStopsQueuedWorkAndAllChildren() async throws {
        let probe = WorkerProbe()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            try await BoundedScanWork.map(Array(0..<100), limit: { 2 }) { value in
                await probe.enter()
                continuation.yield(())
                do { try await Task.sleep(for: .seconds(10)) } catch {
                    await probe.leave()
                    throw error
                }
                await probe.leave()
                return value
            }
        }
        for await _ in stream { task.cancel(); break }
        continuation.finish()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let active = await probe.active
        let started = await probe.started
        XCTAssertEqual(active, 0)
        XCTAssertLessThanOrEqual(started, 2)
    }

    func testAdaptivePolicyRespondsToPowerThermalAndVolume() {
        let policy = ScanWorkerPolicy(maximumWorkers: 4)
        let internalDisk = ScanVolumeInfo(isLocal: true, isInternal: true, isRemovable: false)
        var system = ScanSystemState(processorCount: 10, lowPowerMode: false, thermalState: .nominal)
        XCTAssertEqual(policy.limit(system: system, volume: internalDisk), 4)
        system.lowPowerMode = true
        XCTAssertEqual(policy.limit(system: system, volume: internalDisk), 1)
        system.lowPowerMode = false
        system.thermalState = .critical
        XCTAssertEqual(policy.limit(system: system, volume: internalDisk), 1)
        system.thermalState = .fair
        XCTAssertEqual(policy.limit(system: system, volume: internalDisk), 2)
        system.thermalState = .nominal
        XCTAssertEqual(policy.limit(system: system,
            volume: ScanVolumeInfo(isLocal: false, isInternal: false, isRemovable: true)), 1)
        XCTAssertEqual(policy.limit(system: system,
            volume: ScanVolumeInfo(isLocal: true, isInternal: false, isRemovable: false)), 1)
        system.processorCount = 2
        XCTAssertEqual(policy.limit(system: system, volume: internalDisk), 1)
        XCTAssertEqual(ScanWorkerPolicy(maximumWorkers: 999).maximumWorkers, 4)
        XCTAssertEqual(ScanWorkerPolicy(maximumWorkers: 0).maximumWorkers, 1)
    }

    func testParallelAndSerialResultsHaveIdenticalDeterministicKeepers() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for group in 0..<5 {
            for copy in 0..<4 {
                try Data(repeating: UInt8(group), count: 256 * 1024).write(
                    to: root.appendingPathComponent("g\(group)-\(copy).bin"))
            }
        }
        let serial = try await service(workers: 1).scan(root: root, minimumLargeFileBytes: 1)
        let parallel = try await service(workers: 4).scan(root: root, minimumLargeFileBytes: 1)
        XCTAssertEqual(serial.duplicateGroups.map(\.id), parallel.duplicateGroups.map(\.id))
        XCTAssertEqual(serial.duplicateGroups.map { $0.files.map(\.url) }, parallel.duplicateGroups.map { $0.files.map(\.url) })
        XCTAssertEqual(serial.largeFiles, parallel.largeFiles)
        XCTAssertEqual(parallel.statistics.hashedBytes, UInt64(20 * 256 * 1024))
        XCTAssertEqual(parallel.statistics.verifiedBytes, UInt64(30 * 256 * 1024))
    }

    func testWarmCacheAvoidsHashReadsButAlwaysComparesFullBytes() async throws {
        let root = try duplicateFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = service()
        let cold = try await scanner.scan(root: root)
        let warm = try await scanner.scan(root: root)
        XCTAssertEqual(cold.duplicateGroups.count, 1)
        XCTAssertEqual(warm.duplicateGroups.map(\.id), cold.duplicateGroups.map(\.id))
        XCTAssertEqual(warm.statistics.hashedBytes, 0)
        XCTAssertEqual(warm.statistics.reusedHashBytes, cold.statistics.hashedBytes)
        XCTAssertEqual(warm.statistics.reusedFingerprints, 4)
        XCTAssertEqual(warm.statistics.verifiedBytes, cold.statistics.verifiedBytes)
        XCTAssertGreaterThan(warm.statistics.verifiedBytes, 0)
        await scanner.clearFingerprintCache()
        let cleared = try await scanner.scan(root: root)
        XCTAssertEqual(cleared.statistics.reusedHashBytes, 0)
        XCTAssertEqual(cleared.statistics.hashedBytes, cold.statistics.hashedBytes)
    }

    func testSameSizeMutationWithRestoredModificationTimeInvalidatesCache() async throws {
        let root = try duplicateFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = service()
        _ = try await scanner.scan(root: root)
        let changed = root.appendingPathComponent("a.bin")
        let before = try FileStamp.read(changed)
        try await Task.sleep(for: .milliseconds(5))
        let handle = try FileHandle(forWritingTo: changed)
        try handle.seek(toOffset: 128 * 1024)
        try handle.write(contentsOf: Data([99]))
        var times = [timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
                     timespec(tv_sec: Int(before.modificationSeconds), tv_nsec: Int(before.modificationNanoseconds))]
        XCTAssertEqual(futimens(handle.fileDescriptor, &times), 0)
        try handle.close()
        let after = try FileStamp.read(changed)
        XCTAssertEqual(before.inode, after.inode)
        XCTAssertEqual(before.logicalBytes, after.logicalBytes)
        XCTAssertEqual(before.modificationNanoseconds, after.modificationNanoseconds)
        XCTAssertEqual(before.modificationSeconds, after.modificationSeconds)
        XCTAssertNotEqual(before, after, "ctime must detect this mutation")
        let result = try await scanner.scan(root: root)
        XCTAssertTrue(result.duplicateGroups.isEmpty)
        XCTAssertGreaterThan(result.statistics.hashedBytes, 0)
    }

    func testReplacementAndDeletionCannotReuseOldDuplicateResults() async throws {
        let root = try duplicateFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = service()
        _ = try await scanner.scan(root: root)
        let first = root.appendingPathComponent("a.bin")
        let original = try FileStamp.read(first)
        try Data(repeating: 18, count: 256 * 1024).write(to: first, options: .atomic)
        XCTAssertNotEqual(original.inode, try FileStamp.read(first).inode)
        let changed = try await scanner.scan(root: root)
        XCTAssertTrue(changed.duplicateGroups.isEmpty)
        try FileManager.default.removeItem(at: first)
        let deleted = try await scanner.scan(root: root)
        XCTAssertEqual(deleted.scannedCount, 1)
        XCTAssertTrue(deleted.duplicateGroups.isEmpty)
    }

    func testExternalVolumeAndDisabledReuseReadFullContentAgain() async throws {
        let root = try duplicateFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = service(internalDisk: false)
        _ = try await scanner.scan(root: root)
        let second = try await scanner.scan(root: root)
        XCTAssertEqual(second.statistics.reusedFingerprints, 0)
        XCTAssertGreaterThan(second.statistics.hashedBytes, 0)
        let internalScanner = service()
        _ = try await internalScanner.scan(root: root)
        let disabled = try await internalScanner.scan(root: root, mode: .combined, reuseFingerprints: false)
        XCTAssertEqual(disabled.statistics.reusedFingerprints, 0)
        XCTAssertGreaterThan(disabled.statistics.hashedBytes, 0)
    }

    func testCacheCapacityExpiryAndRootBoundary() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ScanFingerprintCache(capacity: 2)
        for index in 0..<5 {
            let url = root.appendingPathComponent("\(index).bin")
            try Data([UInt8(index)]).write(to: url)
            await cache.store(ScannedFile(url: url, root: root, stamp: try FileStamp.read(url)), sample: "\(index)")
        }
        let count = await cache.count
        XCTAssertLessThanOrEqual(count, 2)
        let unrelated = await cache.snapshot(for: root.appendingPathExtension("other"))
        XCTAssertTrue(unrelated.isEmpty)
        let expired = ScanFingerprintCache(lifetime: .zero)
        let url = root.appendingPathComponent("0.bin")
        await expired.store(ScannedFile(url: url, root: root, stamp: try FileStamp.read(url)), fullHash: "test")
        let snapshot = await expired.snapshot(for: root)
        XCTAssertTrue(snapshot.isEmpty)
    }

    func testConcurrentProgressIsSerializedAndMonotonic() async throws {
        let probe = ProgressProbe()
        let reporter = ScanProgressReporter(
            initial: FileDiscoveryProgress(stage: .hashing, scannedCount: 50, hashedBytes: 0, skippedCount: 0),
            callback: { await probe.receive($0) })
        _ = try await BoundedScanWork.map(Array(0..<50), limit: { 4 }) { value in
            await reporter.update(FileDiscoveryProgress(stage: .hashing, scannedCount: 50,
                hashedBytes: UInt64(value), skippedCount: 0))
            await reporter.completed()
            return value
        }
        let events = await probe.events
        let peak = await probe.peak
        XCTAssertEqual(peak, 1, "Callbacks must not overlap while suspended")
        XCTAssertEqual(events.map(\.hashedBytes), events.map(\.hashedBytes).sorted())
        XCTAssertEqual(events.map(\.completedCandidates), events.map(\.completedCandidates).sorted())
        XCTAssertEqual(events.last?.completedCandidates, 50)
    }

    func testWarmCacheMutationDuringProgressIsRejectedBeforeResults() async throws {
        let root = try duplicateFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let scanner = service()
        _ = try await scanner.scan(root: root)
        let gate = WarmMutationGate(url: root.appendingPathComponent("a.bin"))
        let result = try await scanner.scan(root: root, minimumLargeFileBytes: 1) { event in
            if event.stage == .verifying { await gate.changeOnce() }
        }
        XCTAssertTrue(result.duplicateGroups.isEmpty)
        XCTAssertEqual(result.largeFiles.map { $0.url.lastPathComponent }, ["b.bin"])
        XCTAssertFalse(result.isComplete)
    }

    func testWorkerLimitReductionDrainsInFlightTasksBeforeStartingMore() async throws {
        let capacity = AdjustableWorkerLimit()
        let probe = WorkerProbe()
        _ = try await BoundedScanWork.map(Array(0..<20), limit: { capacity.value }) { value in
            await probe.enter(recordAfterDrain: value >= 4)
            if value == 0 { capacity.reduce() }
            try await Task.sleep(for: .milliseconds(2))
            await probe.leave()
            return value
        }
        let peakAfterDrain = await probe.peakAfterDrain
        XCTAssertEqual(peakAfterDrain, 1)
    }

    private func service(workers: Int = 4, internalDisk: Bool = true) -> FileDiscoveryService {
        FileDiscoveryService(workerPolicy: ScanWorkerPolicy(maximumWorkers: workers, adaptive: false),
            volumeInfo: { _ in ScanVolumeInfo(isLocal: true, isInternal: internalDisk, isRemovable: !internalDisk) })
    }

    private func fixture() throws -> URL {
        let root = FilePathPolicy.normalized(FileManager.default.temporaryDirectory)
            .appendingPathComponent("MacPulseParallel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func duplicateFixture() throws -> URL {
        let root = try fixture()
        for name in ["a.bin", "b.bin"] {
            try Data(repeating: 6, count: 256 * 1024).write(to: root.appendingPathComponent(name))
        }
        return root
    }
}

private actor WorkerProbe {
    var active = 0
    var peak = 0
    var started = 0
    var peakAfterDrain = 0
    func enter(recordAfterDrain: Bool = false) {
        active += 1; started += 1; peak = max(peak, active)
        if recordAfterDrain { peakAfterDrain = max(peakAfterDrain, active) }
    }
    func leave() { active -= 1 }
}

private final class AdjustableWorkerLimit: @unchecked Sendable {
    private let lock = NSLock()
    private var limit = 4
    var value: Int { lock.withLock { limit } }
    func reduce() { lock.withLock { limit = 1 } }
}

private actor WarmMutationGate {
    let url: URL
    var changed = false
    init(url: URL) { self.url = url }
    func changeOnce() {
        guard !changed else { return }
        changed = true
        try? Data(repeating: 29, count: 256 * 1024).write(to: url)
    }
}

private actor ProgressProbe {
    var events: [FileDiscoveryProgress] = []
    private var active = 0
    var peak = 0
    func receive(_ event: FileDiscoveryProgress) async {
        active += 1
        peak = max(peak, active)
        try? await Task.sleep(for: .milliseconds(1))
        events.append(event)
        active -= 1
    }
}
