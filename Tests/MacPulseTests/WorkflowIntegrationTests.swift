import Combine
import XCTest

@testable import MacPulse

@MainActor final class WorkflowIntegrationTests: XCTestCase {
    func testScanMemorySettingsPersistAndAreLockedDuringScanning() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        XCTAssertTrue(fixture.model.reuseScanFingerprints)
        await fixture.model.setReuseScanFingerprints(false)
        XCTAssertFalse(fixture.model.reuseScanFingerprints)
        XCTAssertEqual(fixture.defaults.object(forKey: "macpulse.reuseScanFingerprints") as? Bool, false)
        await fixture.model.clearScanMemory()
        XCTAssertEqual(fixture.model.workflowNotice, .scanMemoryCleared)
        await fixture.model.setReuseScanFingerprints(true)
        try fixture.makeDuplicates()
        fixture.model.acceptScanFolder(fixture.files)
        fixture.model.startFileScan()
        await fixture.model.setReuseScanFingerprints(false)
        XCTAssertTrue(fixture.model.reuseScanFingerprints, "Settings changes must not race an active scan")
        fixture.model.cancelOperation()
        await fixture.model.waitForCurrentOperation()
    }

    func testCacheScanReviewApprovalAndReportUseOneWorkingFlow() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        let cache = try fixture.makeCache()
        await fixture.model.scanCaches()
        XCTAssertEqual(fixture.model.cacheCandidates.count, 1)
        XCTAssertNil(fixture.model.cacheRejection(try XCTUnwrap(fixture.model.cacheCandidates.first)))
        fixture.model.selectedCaches = [cache]
        fixture.model.prepareCacheCleanup()
        let review = try XCTUnwrap(fixture.model.pendingReview)
        XCTAssertEqual(review.actions.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path), "Preview must not move anything")
        fixture.model.approveCleanup(review)
        await fixture.model.waitForCurrentOperation()
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertEqual(fixture.model.presentedReport?.succeededCount, 1)
        XCTAssertTrue(fixture.model.activityRecords.contains { $0.kind == .cacheCleanup && $0.status == .completed })
        XCTAssertEqual(fixture.model.operation, .idle)
    }

    func testSmartBoostStartsUnselectedAndExecutesOnlyApprovedCache() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        let cache = try fixture.makeCache()
        fixture.model.startBoost()
        await fixture.model.waitForCurrentOperation()
        XCTAssertEqual(fixture.model.boostStage, .review)
        XCTAssertTrue(fixture.model.selectedBoostActions.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        fixture.model.boostSelectedCaches = [cache]
        XCTAssertEqual(fixture.model.selectedBoostActions.count, 1)
        fixture.model.approveBoost()
        await fixture.model.waitForCurrentOperation()
        XCTAssertEqual(fixture.model.boostStage, .results)
        XCTAssertEqual(fixture.model.boostReport?.succeededCount, 1)
        XCTAssertNotNil(fixture.model.boostReport?.before)
        XCTAssertNotNil(fixture.model.boostReport?.after)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testDuplicateKeeperCanBeChangedAndSurvivesApprovedCleanup() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.makeDuplicates()
        fixture.model.acceptScanFolder(fixture.files)
        fixture.model.updateLargeThreshold(1)
        fixture.model.startFileScan()
        await fixture.model.waitForCurrentOperation()
        let group = try XCTUnwrap(fixture.model.fileResult?.duplicateGroups.first)
        let keeper = try XCTUnwrap(group.files.last)
        let selected = try XCTUnwrap(group.files.first)
        fixture.model.keepDuplicate(keeper, in: group)
        fixture.model.selectedDuplicates = [selected.url]
        fixture.model.prepareFileCleanup(duplicates: true)
        let review = try XCTUnwrap(fixture.model.pendingReview)
        if case .trash(let target) = review.actions[0] {
            XCTAssertEqual(target.keeperURL, keeper.url)
        } else {
            XCTFail("Expected a verified duplicate Trash target")
        }
        fixture.model.approveCleanup(review)
        await fixture.model.waitForCurrentOperation()
        XCTAssertTrue(FileManager.default.fileExists(atPath: keeper.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: selected.url.path))
        XCTAssertEqual(fixture.model.presentedReport?.succeededCount, 1)
    }

    func testLargeFileTabCannotBypassDuplicateKeeperPolicy() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.makeDuplicates()
        fixture.model.acceptScanFolder(fixture.files)
        fixture.model.updateLargeThreshold(1)
        fixture.model.startFileScan()
        await fixture.model.waitForCurrentOperation()
        let result = try XCTUnwrap(fixture.model.fileResult)
        XCTAssertEqual(result.largeFiles.count, 2)
        fixture.model.selectedLargeFiles = Set(result.largeFiles.map(\.url))
        fixture.model.prepareFileCleanup(duplicates: false)
        XCTAssertNil(fixture.model.pendingReview)
        XCTAssertEqual(fixture.model.workflowNotice, .keepAtLeastOne)
        XCTAssertTrue(result.largeFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.url.path) })
    }

    func testCancelButtonStateReturnsToIdleWithoutChangingFiles() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.makeDuplicates()
        fixture.model.acceptScanFolder(fixture.files)
        fixture.model.startFileScan()
        fixture.model.cancelOperation()
        await fixture.model.waitForCurrentOperation()
        XCTAssertEqual(fixture.model.operation, .idle)
        XCTAssertEqual(fixture.model.workflowNotice, .operationCancelled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.files.path).count, 2)
    }

    func testLargeFileScreenDoesNotStartDuplicateHashing() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.makeDuplicates()
        fixture.model.acceptScanFolder(fixture.files)
        fixture.model.updateLargeThreshold(1)
        fixture.model.storageMode = 1
        fixture.model.startFileScan()
        await fixture.model.waitForCurrentOperation()
        let result = try XCTUnwrap(fixture.model.fileResult)
        XCTAssertEqual(result.largeFiles.count, 2)
        XCTAssertFalse(result.duplicatesScanned)
        XCTAssertEqual(fixture.model.fileScanProgress?.stage, .enumerating)
        XCTAssertEqual(fixture.model.operation, .idle)
    }

    func testCancellingDuplicateScanKeepsTheAlreadyPublishedLargeFiles() async throws {
        let fixture = try WorkflowFixture()
        defer { fixture.cleanup() }
        try fixture.makeDuplicates()
        fixture.model.acceptScanFolder(fixture.files)
        fixture.model.updateLargeThreshold(1)
        fixture.model.storageMode = 2
        let subscription = fixture.model.$fileResult.sink { result in
            if result?.duplicatesScanned == false { fixture.model.cancelOperation() }
        }
        fixture.model.startFileScan()
        await fixture.model.waitForCurrentOperation()
        subscription.cancel()
        XCTAssertEqual(fixture.model.fileResult?.largeFiles.count, 2)
        XCTAssertFalse(try XCTUnwrap(fixture.model.fileResult).duplicatesScanned)
        XCTAssertEqual(fixture.model.operation, .idle)
        XCTAssertEqual(fixture.model.workflowNotice, .scanCancelledPartial)
    }
}

@MainActor private final class WorkflowFixture {
    let root: URL
    let caches: URL
    let files: URL
    let model: DashboardModel
    let defaults: UserDefaults
    let suite: String

    init() throws {
        root = FilePathPolicy.normalized(
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        caches = root.appendingPathComponent("Caches")
        files = root.appendingPathComponent("Files")
        let trash = root.appendingPathComponent("FixtureTrash")
        for url in [caches, files, trash] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        suite = "MacPulse.WorkflowTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        let executor = ActionExecutor(
            provider: WorkflowTestProvider(),
            trashService: TrashService(cacheRoot: caches, mover: WorkflowFixtureTrash(root: trash)),
            sampleInterval: .milliseconds(1))
        model = DashboardModel(
            provider: WorkflowTestProvider(), cacheRoot: caches, executor: executor,
            activityStore: ActivityStore(defaults: defaults), defaults: defaults)
    }

    func makeCache() throws -> URL {
        let folder = caches.appendingPathComponent("org.fixture.closed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 16384).write(to: folder.appendingPathComponent("cache.bin"))
        return folder
    }

    func makeDuplicates() throws {
        let data = Data(repeating: 42, count: 1_048_576)
        try data.write(to: files.appendingPathComponent("one.bin"))
        try data.write(to: files.appendingPathComponent("two.bin"))
    }

    func cleanup() {
        model.cancelOperation()
        model.stopMonitoring()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

private struct WorkflowFixtureTrash: TrashMoving {
    let root: URL
    func moveToTrash(_ url: URL) throws -> URL {
        let destination = root.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

@MainActor private final class WorkflowTestProvider: SystemMetricsProvider {
    func snapshot() async throws -> PerformanceSnapshot {
        PerformanceSnapshot(
            timestamp: .now, cpu: CPUReading(total: 20, user: 12, system: 8, idle: 80, isAvailable: true),
            memory: MemoryReading(
                physicalBytes: 8192, appBytes: 2048, wiredBytes: 0, compressedBytes: 0, swapUsedBytes: 0,
                pressure: .healthy, estimatedAvailableFraction: 0.5),
            storage: StorageReading(totalBytes: 100000, availableBytes: 50000),
            thermal: ThermalReading(state: .nominal, health: .healthy), processes: [])
    }
}
