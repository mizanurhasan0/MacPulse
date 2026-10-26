import XCTest

@testable import MacPulse

@MainActor final class ActionExecutorTests: XCTestCase {
    func testPlanRunsOncePerIdentityAndReportsComparableMeasurements() async {
        let quitter = ExecutionTestQuitter()
        let executor = ActionExecutor(
            provider: ExecutionTestProvider(), quitter: quitter, sampleInterval: .milliseconds(1))
        let target = process(200)
        let report = await executor.execute([.quit(target), .quit(target)]) { _ in }
        XCTAssertEqual(quitter.pids, [200])
        XCTAssertEqual(report.succeededCount, 1)
        XCTAssertEqual(report.before?.averageCPU, 25)
        XCTAssertEqual(report.after?.averageCPU, 55)
        XCTAssertEqual(report.before?.cpuSampleCount, 2)
        XCTAssertEqual(report.after?.cpuSampleCount, 2)
        XCTAssertEqual(report.movedEstimatedBytes, 0)
        XCTAssertEqual(report.storageChange, 0)
    }

    func testFailedBaselinePreventsAnyAction() async {
        let provider = ExecutionTestProvider()
        provider.fail = true
        let quitter = ExecutionTestQuitter()
        let executor = ActionExecutor(provider: provider, quitter: quitter, sampleInterval: .milliseconds(1))
        let report = await executor.execute([.quit(process(201))]) { _ in }
        XCTAssertTrue(quitter.pids.isEmpty)
        XCTAssertNil(report.before)
        XCTAssertEqual(report.items.first?.outcome, .failed)
    }

    func testCancellationBeforeExecutionDoesNotQuitAnApplication() async {
        let quitter = ExecutionTestQuitter()
        let executor = ActionExecutor(provider: ExecutionTestProvider(), quitter: quitter, sampleInterval: .seconds(1))
        let target = process(202)
        let task = Task { await executor.execute([.quit(target)]) { _ in } }
        task.cancel()
        let report = await task.value
        XCTAssertTrue(report.wasCancelled)
        XCTAssertTrue(quitter.pids.isEmpty)
        XCTAssertEqual(report.items.first?.outcome, .cancelled)
    }

    func testCentralExecutorRejectsDeletingEveryVerifiedDuplicate() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.bin")
        let second = root.appendingPathComponent("second.bin")
        try Data("identical content".utf8).write(to: first)
        try Data("identical content".utf8).write(to: second)
        let a = try FileStamp.read(first)
        let b = try FileStamp.read(second)
        let actions: [PlannedAction] = [
            .trash(
                TrashTarget(
                    url: first, root: root, stamp: a, category: .reviewedFile, keeperURL: second, keeperStamp: b)),
            .trash(
                TrashTarget(
                    url: second, root: root, stamp: b, category: .reviewedFile, keeperURL: first, keeperStamp: a)),
        ]
        let executor = ActionExecutor(
            provider: ExecutionTestProvider(), quitter: ExecutionTestQuitter(),
            trashService: TrashService(mover: NeverMoveTestTrash()), sampleInterval: .milliseconds(1))
        let report = await executor.execute(actions) { _ in }
        XCTAssertEqual(report.succeededCount, 0)
        XCTAssertEqual(report.items.map(\.outcome), [.failed, .failed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testGracefulQuitterRejectsProtectedIdentity() async {
        let target = ProcessReading(
            pid: 1, name: "protected", bundleIdentifier: "com.apple.launchd", memoryBytes: 0,
            cpuPercent: nil, executablePath: "/sbin/launchd", launchDate: .now)
        let result = await GracefulApplicationQuitter().quit(target)
        XCTAssertEqual(result.outcome, .changed)
    }

    private func process(_ pid: Int32) -> ProcessReading {
        ProcessReading(
            pid: pid, name: "Fixture app", bundleIdentifier: "test.fixture", memoryBytes: 1024,
            cpuPercent: 4, executablePath: "/Applications/Fixture.app/Contents/MacOS/Fixture", launchDate: .now)
    }
}

@MainActor private final class ExecutionTestProvider: SystemMetricsProvider {
    var count = 0
    var fail = false
    func snapshot() async throws -> PerformanceSnapshot {
        if fail { throw CocoaError(.fileReadNoPermission) }
        count += 1
        return PerformanceSnapshot(
            timestamp: .now,
            cpu: CPUReading(total: Double(count * 10), user: 0, system: 0, idle: 0, isAvailable: true),
            memory: MemoryReading(
                physicalBytes: 8192, appBytes: 2048, wiredBytes: 0, compressedBytes: 0,
                swapUsedBytes: 0, pressure: .healthy, estimatedAvailableFraction: 0.5),
            storage: StorageReading(totalBytes: 100000, availableBytes: 50000),
            thermal: ThermalReading(state: .nominal, health: .healthy), processes: [])
    }
}

@MainActor private final class ExecutionTestQuitter: ApplicationQuitting {
    var pids: [Int32] = []
    func quit(_ target: ProcessReading) async -> ActionItemResult {
        pids.append(target.pid)
        return ActionItemResult(title: target.name, outcome: .quit)
    }
}

private struct NeverMoveTestTrash: TrashMoving {
    func moveToTrash(_ url: URL) throws -> URL {
        XCTFail("No duplicate should reach Trash when all copies are selected")
        throw CocoaError(.fileWriteNoPermission)
    }
}
