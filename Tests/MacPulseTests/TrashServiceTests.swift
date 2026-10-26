import XCTest

@testable import MacPulse

@MainActor final class TrashServiceTests: XCTestCase {
    func testReviewedFileMovesToFixtureTrashWithoutDeletingOtherFiles() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = try write("selected.bin", in: fixture, data: Data(repeating: 3, count: 32_768))
        let sentinel = try write("keep.bin", in: fixture, data: Data([4, 5]))
        let target = TrashTarget(url: file, root: fixture, stamp: try FileStamp.read(file), category: .reviewedFile)
        let result = await service(in: fixture).move(targets: [target])
        XCTAssertEqual(result.movedCount, 1)
        XCTAssertEqual(result.failedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([4, 5]))
        let destination = try XCTUnwrap(result.items.first?.trashURL)
        XCTAssertEqual(try Data(contentsOf: destination), Data(repeating: 3, count: 32_768))
        XCTAssertEqual(result.movedEstimatedBytes, target.estimatedBytes)
        XCTAssertFalse(try children(fixture).contains { $0.lastPathComponent.hasPrefix(".MacPulse-") })
    }

    func testStaleFileIsRejectedAndReplacementSurvives() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = try write("selected", in: fixture, data: Data([1]))
        let stamp = try FileStamp.read(file)
        try Data([7, 8, 9]).write(to: file)
        let result = await service(in: fixture).move(targets: [
            TrashTarget(url: file, root: fixture, stamp: stamp, category: .reviewedFile)
        ])
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(try Data(contentsOf: file), Data([7, 8, 9]))
    }

    func testRootAndOutsideFileAreRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let authorized = fixture.appendingPathComponent("allowed", isDirectory: true)
        try FileManager.default.createDirectory(at: authorized, withIntermediateDirectories: true)
        let outside = try write("outside", in: fixture, data: Data([1]))
        let result = await service(in: fixture).move(targets: [
            TrashTarget(
                url: authorized, root: authorized, stamp: try FileStamp.read(authorized), category: .reviewedFile),
            TrashTarget(url: outside, root: authorized, stamp: try FileStamp.read(outside), category: .reviewedFile),
        ])
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: authorized.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testSymlinkedAncestorAndApplicationPackageAreRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let real = fixture.appendingPathComponent("real", isDirectory: true)
        let package = fixture.appendingPathComponent("Protected.app", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let original = try write("data", in: real, data: Data([1]))
        let bundled = try write("data", in: package, data: Data([2]))
        let link = fixture.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let linkedFile = link.appendingPathComponent("data")
        let result = await service(in: fixture).move(targets: [
            TrashTarget(url: linkedFile, root: fixture, stamp: try FileStamp.read(linkedFile), category: .reviewedFile),
            TrashTarget(url: bundled, root: fixture, stamp: try FileStamp.read(bundled), category: .reviewedFile),
        ])
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundled.path))
        XCTAssertThrowsError(try FilePathPolicy.openDirectory(link))
    }

    func testEligibleCacheMovesAndProtectedCachesDoNot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let cacheRoot = fixture.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let names = ["org.example.closed", "com.apple.protected", "org.example.running", "MacPulse"]
        for name in names {
            let folder = cacheRoot.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try write("data", in: folder, data: Data(repeating: 2, count: 4096))
        }
        let candidates = try await SafeStorageScanner().scan(root: cacheRoot)
        XCTAssertEqual(candidates.count, names.count)
        let targets = try candidates.map { try TrashTarget.cache($0, root: cacheRoot) }
        let result = await TrashService(
            cacheRoot: cacheRoot, mover: FixtureTrashMover(root: fixture.appendingPathComponent("Trash"))
        )
        .move(targets: targets, runningBundleIDs: ["org.example.running"])
        XCTAssertEqual(result.movedCount, 1)
        XCTAssertEqual(result.failedCount, 3)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: cacheRoot.appendingPathComponent("org.example.closed").path))
        for name in names.dropFirst() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: cacheRoot.appendingPathComponent(name).path))
        }
    }

    func testIncompleteCacheIsRejectedByService() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let cache = fixture.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        _ = try write("data", in: cache, data: Data(repeating: 4, count: 4096))
        let candidate = CleanupCandidate(
            url: cache, displayName: "cache", allocatedBytes: 4096,
            explanation: "", risk: "Review", isComplete: false, stamp: try FileStamp.read(cache))
        let result = await TrashService(
            cacheRoot: fixture, mover: FixtureTrashMover(root: fixture.appendingPathComponent("Trash"))
        )
        .move(targets: [try TrashTarget.cache(candidate, root: fixture)])
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testDuplicateKeeperSurvivesAndSelectedDuplicateMoves() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let contents = Data(repeating: 8, count: 400_000)
        let keeper = try write("keep", in: fixture, data: contents)
        let copy = try write("copy", in: fixture, data: contents)
        let result = await service(in: fixture).move(targets: [
            TrashTarget(
                url: copy, root: fixture, stamp: try FileStamp.read(copy), category: .reviewedFile,
                keeperURL: keeper, keeperStamp: try FileStamp.read(keeper))
        ])
        XCTAssertEqual(result.movedCount, 1)
        XCTAssertEqual(try Data(contentsOf: keeper), contents)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    func testSelectingAllDuplicateCopiesIsRejected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let a = try write("a", in: fixture, data: Data([1, 2, 3]))
        let b = try write("b", in: fixture, data: Data([1, 2, 3]))
        let aStamp = try FileStamp.read(a)
        let bStamp = try FileStamp.read(b)
        let result = await service(in: fixture).move(targets: [
            TrashTarget(
                url: a, root: fixture, stamp: aStamp, category: .reviewedFile, keeperURL: b, keeperStamp: bStamp),
            TrashTarget(
                url: b, root: fixture, stamp: bStamp, category: .reviewedFile, keeperURL: a, keeperStamp: aStamp),
        ])
        XCTAssertEqual(result.failedCount, 2)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
    }

    func testSameSizeDifferentContentsAreNotTreatedAsDuplicates() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let keeper = try write("keep", in: fixture, data: Data([1, 2, 3]))
        let copy = try write("copy", in: fixture, data: Data([4, 5, 6]))
        let result = await service(in: fixture).move(targets: [
            TrashTarget(
                url: copy, root: fixture, stamp: try FileStamp.read(copy), category: .reviewedFile,
                keeperURL: keeper, keeperStamp: try FileStamp.read(keeper))
        ])
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy.path))
    }

    func testCancellationLeavesSelectedFilesUntouched() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = try write("data", in: fixture, data: Data([1]))
        let target = TrashTarget(url: file, root: fixture, stamp: try FileStamp.read(file), category: .reviewedFile)
        let service = service(in: fixture)
        let task = Task { await service.move(targets: [target]) }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testMoverFailureRestoresOriginalAndRemovesEmptyStage() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = try write("data", in: fixture, data: Data([1, 2]))
        let target = TrashTarget(url: file, root: fixture, stamp: try FileStamp.read(file), category: .reviewedFile)
        let result = await TrashService(mover: FailingTrashMover()).move(targets: [target])
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(try Data(contentsOf: file), Data([1, 2]))
        XCTAssertFalse(try children(fixture).contains { $0.lastPathComponent.hasPrefix(".MacPulse-") })
    }

    func testFailedRestoreNeverOverwritesAConcurrentReplacement() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let file = try write("data", in: fixture, data: Data([1, 2]))
        let target = TrashTarget(url: file, root: fixture, stamp: try FileStamp.read(file), category: .reviewedFile)
        let result = await TrashService(mover: CollidingTrashMover(originalURL: file)).move(targets: [target])
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(try Data(contentsOf: file), Data([9]))
        let stage = try XCTUnwrap(try children(fixture).first { $0.lastPathComponent.hasPrefix(".MacPulse-") })
        XCTAssertEqual(try Data(contentsOf: stage.appendingPathComponent("data")), Data([1, 2]))
        XCTAssertTrue(result.items[0].message.contains(stage.path))
    }

    func testCacheNestedContentChangeIsRejectedAfterPreview() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let cache = fixture.appendingPathComponent("org.example.closed", isDirectory: true)
        let nested = cache.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let file = try write("data.bin", in: nested, data: Data(repeating: 1, count: 4096))
        let scanned = try await SafeStorageScanner().scan(root: fixture)
        let candidate = try XCTUnwrap(scanned.first)
        // Updating an existing nested file need not change the immediate cache folder's metadata.
        try Data(repeating: 9, count: 4096).write(to: file)
        let result = await TrashService(
            cacheRoot: fixture, mover: FixtureTrashMover(root: fixture.appendingPathComponent("Trash"))
        )
        .move(targets: [try TrashTarget.cache(candidate, root: fixture)])
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.movedCount, 0)
        XCTAssertEqual(try Data(contentsOf: file), Data(repeating: 9, count: 4096))
    }

    func testCacheIsProtectedWhenApplicationStartsAfterScan() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let cache = fixture.appendingPathComponent("org.example.closed", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        _ = try write("data.bin", in: cache, data: Data(repeating: 1, count: 4096))
        let scanned = try await SafeStorageScanner().scan(root: fixture)
        let candidate = try XCTUnwrap(scanned.first)
        XCTAssertNil(
            CacheProtectionPolicy.rejectionReason(candidate: candidate, runningBundleIDs: [], cacheRoot: fixture))
        let result = await TrashService(
            cacheRoot: fixture, mover: FixtureTrashMover(root: fixture.appendingPathComponent("Trash"))
        )
        .move(targets: [try TrashTarget.cache(candidate, root: fixture)], runningBundleIDs: ["org.example.closed"])
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
    }

    func testMidBatchCancellationKeepsRemainingItems() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let files = try ["one.bin", "two.bin", "three.bin"].map { try write($0, in: fixture, data: Data([3, 4, 5])) }
        let targets = try files.map {
            TrashTarget(url: $0, root: fixture, stamp: try FileStamp.read($0), category: .reviewedFile)
        }
        let cancel = TrashCancellationHandle()
        let service = service(in: fixture)
        let task = Task {
            await service.move(
                targets: targets,
                progress: { completed, _ in
                    if completed == 1 { cancel.cancel() }
                })
        }
        cancel.set(task)
        let result = await task.value
        XCTAssertEqual(result.movedCount, 1)
        XCTAssertEqual(result.items.filter { $0.status == .cancelled }.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[1].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[2].path))
    }

    func testSeparateQueuedRequestsStillPreserveLastDuplicate() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let a = try write("a.bin", in: fixture, data: Data([1, 2, 3]))
        let b = try write("b.bin", in: fixture, data: Data([1, 2, 3]))
        let aStamp = try FileStamp.read(a)
        let bStamp = try FileStamp.read(b)
        let first = TrashTarget(
            url: a, root: fixture, stamp: aStamp, category: .reviewedFile, keeperURL: b, keeperStamp: bStamp)
        let second = TrashTarget(
            url: b, root: fixture, stamp: bStamp, category: .reviewedFile, keeperURL: a, keeperStamp: aStamp)
        let service = service(in: fixture)
        let initial = await service.move(targets: [first])
        let queued = await service.move(targets: [second])
        XCTAssertEqual(initial.movedCount, 1)
        XCTAssertEqual(queued.failedCount, 1)
        XCTAssertEqual(try Data(contentsOf: b), Data([1, 2, 3]))
    }

    func testCredentialSourceAndDatabaseFilesAreProtected() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let names = ["secret.pem", "private.key", "App.swift", "package.json", "important.sqlite", ".env"]
        let files = try names.map { try write($0, in: fixture, data: Data([2, 5])) }
        let targets = try files.map {
            TrashTarget(url: $0, root: fixture, stamp: try FileStamp.read($0), category: .reviewedFile)
        }
        let result = await service(in: fixture).move(targets: targets)
        XCTAssertEqual(result.failedCount, files.count)
        XCTAssertEqual(result.movedCount, 0)
        for file in files { XCTAssertTrue(FileManager.default.fileExists(atPath: file.path)) }
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("MacPulseTrash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ name: String, in root: URL, data: Data) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func service(in root: URL) -> TrashService {
        TrashService(mover: FixtureTrashMover(root: root.appendingPathComponent("Trash")))
    }

    private func children(_ root: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    }
}

private struct FixtureTrashMover: TrashMoving {
    let root: URL
    func moveToTrash(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }
}

private struct FailingTrashMover: TrashMoving {
    func moveToTrash(_ url: URL) throws -> URL { throw CocoaError(.fileWriteNoPermission) }
}

private struct CollidingTrashMover: TrashMoving {
    let originalURL: URL
    func moveToTrash(_ url: URL) throws -> URL {
        try Data([9]).write(to: originalURL)
        throw CocoaError(.fileWriteNoPermission)
    }
}

private final class TrashCancellationHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<TrashBatchResult, Never>?
    func set(_ task: Task<TrashBatchResult, Never>) { lock.withLock { self.task = task } }
    func cancel() { lock.withLock { task?.cancel() } }
}
