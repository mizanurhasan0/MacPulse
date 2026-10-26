import Foundation
import XCTest

@testable import MacPulse

@MainActor final class FileDiscoveryTests: XCTestCase {
    func testDuplicateDetectionRequiresContentEqualityNotSizeOrName() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 11, count: 8192).write(to: root.appendingPathComponent("first.bin"))
        try Data(repeating: 11, count: 8192).write(to: root.appendingPathComponent("renamed-copy.bin"))
        try Data(repeating: 12, count: 8192).write(to: root.appendingPathComponent("different.bin"))

        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 1)
        XCTAssertEqual(result.scannedCount, 3)
        XCTAssertEqual(result.largeFiles.count, 3)
        XCTAssertEqual(result.duplicateGroups.count, 1)
        let duplicates = try XCTUnwrap(result.duplicateGroups.first)
        XCTAssertEqual(Set(duplicates.files.map { $0.url.lastPathComponent }), ["first.bin", "renamed-copy.bin"])
        XCTAssertEqual(duplicates.redundantBytes, 8192)
        XCTAssertEqual(duplicates.keeper.url.lastPathComponent, "first.bin")
        XCTAssertTrue(result.isComplete)
    }

    func testLargeFileThresholdAndDescendingOrder() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for (name, size) in [("small", 1000), ("boundary", 2000), ("large", 3000)] {
            try Data(repeating: 1, count: size).write(to: root.appendingPathComponent(name))
        }
        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 2000)
        XCTAssertEqual(result.largeFiles.map(\.logicalBytes), [3000, 2000])
        XCTAssertEqual(result.largeFiles.map { $0.url.lastPathComponent }, ["large", "boundary"])
        XCTAssertTrue(result.duplicateGroups.isEmpty)
    }

    func testHardLinksAreOnePhysicalFileRatherThanDuplicateCopies() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original")
        try Data(repeating: 2, count: 8192).write(to: original)
        try FileManager.default.linkItem(at: original, to: root.appendingPathComponent("hard-link"))
        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 1)
        XCTAssertEqual(result.scannedCount, 1)
        XCTAssertEqual(result.largeFiles.count, 1)
        XCTAssertTrue(result.duplicateGroups.isEmpty)
        XCTAssertEqual(result.skippedCount, 1)
    }

    func testSymlinkedFileAndDirectoryDoNotEscapeSelectedRoot() async throws {
        let fixtureRoot = try fixture()
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let selected = fixtureRoot.appendingPathComponent("selected", isDirectory: true)
        let outside = fixtureRoot.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let external = outside.appendingPathComponent("private.data")
        try Data(repeating: 4, count: 12_000).write(to: external)
        try Data(repeating: 3, count: 4096).write(to: selected.appendingPathComponent("local.data"))
        try FileManager.default.createSymbolicLink(
            at: selected.appendingPathComponent("linked-file"), withDestinationURL: external)
        try FileManager.default.createSymbolicLink(
            at: selected.appendingPathComponent("linked-folder"), withDestinationURL: outside)
        let result = try await FileDiscoveryService().scan(root: selected, minimumLargeFileBytes: 1)
        XCTAssertEqual(result.largeFiles.map { $0.url.lastPathComponent }, ["local.data"])
        XCTAssertEqual(result.skippedCount, 2)
        XCTAssertFalse(result.isComplete)
    }

    func testApplicationPackagesAndHiddenDirectoriesAreSkipped() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Example.app", ".hidden"] {
            let folder = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 5, count: 4096).write(to: folder.appendingPathComponent("data"))
        }
        try Data(repeating: 8, count: 512).write(to: root.appendingPathComponent("visible"))
        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 1)
        XCTAssertEqual(result.largeFiles.map { $0.url.lastPathComponent }, ["visible"])
        XCTAssertEqual(result.skippedCount, 2)
    }

    func testChangedFileIsExcludedBeforeDuplicateVerification() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a")
        try Data(repeating: 1, count: 16384).write(to: first)
        try Data(repeating: 1, count: 16384).write(to: root.appendingPathComponent("b"))
        let gate = MutationGate(url: first)
        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 1) { progress in
            if progress.stage == .verifying { await gate.mutateOnce() }
        }
        XCTAssertTrue(result.duplicateGroups.isEmpty)
        XCTAssertFalse(result.largeFiles.contains(where: { $0.url == FilePathPolicy.normalized(first) }))
        XCTAssertFalse(result.isComplete)
        XCTAssertGreaterThanOrEqual(result.skippedCount, 1)
    }

    func testPreCancelledScanThrowsWithoutReturningAResult() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let task = Task { try await FileDiscoveryService().scan(root: root) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled scan returned a result")
        } catch is CancellationError {}
    }

    func testAFileChangedMidStreamCannotBecomeADuplicate() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let length = 32 * 1024 * 1024
        let first = root.appendingPathComponent("a")
        try Data(repeating: 1, count: length).write(to: first)
        try Data(repeating: 1, count: length).write(to: root.appendingPathComponent("b"))
        let gate = MutationGate(url: first, size: length)
        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 1) { progress in
            if progress.stage == .hashing, progress.hashedBytes >= 16 * 1024 * 1024 {
                await gate.mutateOnce()
            }
        }
        XCTAssertTrue(result.duplicateGroups.isEmpty)
        XCTAssertEqual(result.largeFiles.map { $0.url.lastPathComponent }, ["b"])
        XCTAssertFalse(result.isComplete)
        XCTAssertGreaterThanOrEqual(result.skippedCount, 1)
    }

    func testCancellationWhileHashingPropagatesToWorker() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 9, count: 4 * 1024 * 1024).write(to: root.appendingPathComponent("a"))
        try Data(repeating: 9, count: 4 * 1024 * 1024).write(to: root.appendingPathComponent("b"))
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let task = Task {
            try await FileDiscoveryService().scan(root: root) { progress in
                if progress.stage == .hashing {
                    continuation.yield(())
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
        for await _ in stream {
            task.cancel()
            break
        }
        continuation.finish()
        do {
            _ = try await task.value
            XCTFail("Cancelled hashing returned a result")
        } catch is CancellationError {}
    }

    func testWholeFilesystemAndSymlinkRootsAreRejected() async throws {
        do {
            _ = try await FileDiscoveryService().scan(root: URL(fileURLWithPath: "/"))
            XCTFail("Root filesystem must be rejected")
        } catch {}
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real", isDirectory: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: real)
        do {
            _ = try await FileDiscoveryService().scan(root: alias)
            XCTFail("Symlink roots must be rejected")
        } catch {}
    }

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MacPulseDiscovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testLargeOnlyReturnsMetadataWithoutHashingOrDuplicateWork() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["one.bin", "two.bin"] {
            try Data(repeating: 5, count: 2 * 1024 * 1024).write(to: root.appendingPathComponent(name))
        }
        let events = DiscoveryEvents()
        let result = try await FileDiscoveryService().scan(
            root: root, minimumLargeFileBytes: 1, mode: .largeFiles,
            progress: { await events.record($0) })
        XCTAssertEqual(result.largeFiles.count, 2)
        XCTAssertFalse(result.duplicatesScanned)
        XCTAssertTrue(result.duplicateGroups.isEmpty)
        let updates = await events.updates
        XCTAssertFalse(updates.isEmpty)
        XCTAssertTrue(updates.allSatisfy { $0.stage == .enumerating && $0.hashedBytes == 0 })
    }

    func testBeginningAndEndMatchesStillRequireFullContentHash() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = Data(repeating: 9, count: 256 * 1024)
        var second = first
        second[128 * 1024] = 8
        try first.write(to: root.appendingPathComponent("one.bin"))
        try second.write(to: root.appendingPathComponent("two.bin"))
        let events = DiscoveryEvents()
        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 1) {
            await events.record($0)
        }
        XCTAssertTrue(result.duplicatesScanned)
        XCTAssertTrue(result.duplicateGroups.isEmpty, "Matching quick samples must never be treated as proof")
        let updates = await events.updates
        XCTAssertTrue(updates.contains { $0.stage == .fingerprinting })
        XCTAssertEqual(updates.last?.hashedBytes, UInt64(first.count + second.count))
        XCTAssertEqual(updates.last?.totalHashBytes, UInt64(first.count + second.count))
    }

    func testQuickSamplesRejectDifferentCandidatesWithoutFullHashing() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 256 * 1024).write(to: root.appendingPathComponent("one.bin"))
        try Data(repeating: 2, count: 256 * 1024).write(to: root.appendingPathComponent("two.bin"))
        let events = DiscoveryEvents()
        let result = try await FileDiscoveryService().scan(root: root) { await events.record($0) }
        XCTAssertTrue(result.duplicateGroups.isEmpty)
        let updates = await events.updates
        XCTAssertFalse(updates.contains { $0.stage == .hashing })
        XCTAssertEqual(updates.last?.hashedBytes, 0)
    }

    func testFileListingIsPublishedBeforeDuplicateHashing() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["one.bin", "two.bin"] {
            try Data(repeating: 4, count: 8192).write(to: root.appendingPathComponent(name))
        }
        let events = DiscoveryEvents()
        _ = try await FileDiscoveryService().scan(
            root: root, minimumLargeFileBytes: 1, mode: .combined,
            enumerated: { await events.listed($0) }, progress: { await events.record($0) })
        let published = await events.preliminary
        XCTAssertEqual(published?.largeFiles.count, 2)
        XCTAssertFalse(try XCTUnwrap(published).duplicatesScanned)
        let listingPrecededHashing = await events.listingPrecededHashing
        XCTAssertTrue(listingPrecededHashing)
    }

    func testFileLimitIsReportedWithoutPretendingTheFolderWasComplete() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["one.bin", "two.bin", "three.bin"] {
            try Data([1, 2, 3]).write(to: root.appendingPathComponent(name))
        }
        let events = DiscoveryEvents()
        let result = try await FileDiscoveryService().scan(
            root: root, minimumLargeFileBytes: 1,
            mode: .largeFiles, maximumFiles: 2, progress: { await events.record($0) })
        XCTAssertEqual(result.scannedCount, 2)
        XCTAssertTrue(result.stoppedAtLimit)
        XCTAssertFalse(result.isComplete)
        let updates = await events.updates
        XCTAssertTrue(updates.last?.stoppedAtLimit == true)
    }

    func testNestedDependencyTreesAreSkipped() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let dependency = root.appendingPathComponent("node_modules/package", isDirectory: true)
        try FileManager.default.createDirectory(at: dependency, withIntermediateDirectories: true)
        try Data(repeating: 5, count: 4096).write(to: dependency.appendingPathComponent("bundle.bin"))
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("personal.bin"))
        let result = try await FileDiscoveryService().scan(root: root, minimumLargeFileBytes: 1, mode: .largeFiles)
        XCTAssertEqual(result.largeFiles.map { $0.url.lastPathComponent }, ["personal.bin"])
        XCTAssertEqual(result.skippedCount, 1)
    }

    func testLargeDuplicateVerificationReportsBytesWhileComparing() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data(repeating: 6, count: 32 * 1024 * 1024)
        try data.write(to: root.appendingPathComponent("one.bin"))
        try data.write(to: root.appendingPathComponent("two.bin"))
        let events = DiscoveryEvents()
        let result = try await FileDiscoveryService().scan(root: root) { await events.record($0) }
        XCTAssertEqual(result.duplicateGroups.count, 1)
        let updates = await events.updates
        XCTAssertTrue(updates.contains { $0.stage == .verifying && $0.verifiedBytes >= 16 * 1024 * 1024 })
        XCTAssertEqual(updates.last?.hashedBytes, UInt64(data.count * 2))
        XCTAssertEqual(updates.last?.verifiedBytes, UInt64(data.count * 2))
    }
}

private actor DiscoveryEvents {
    var updates: [FileDiscoveryProgress] = []
    var preliminary: FileDiscoveryResult?
    var listingPrecededHashing = false
    func listed(_ result: FileDiscoveryResult) { preliminary = result }
    func record(_ progress: FileDiscoveryProgress) {
        updates.append(progress)
        if progress.stage == .hashing && preliminary != nil { listingPrecededHashing = true }
    }
}

private actor MutationGate {
    let url: URL
    let size: Int
    private var mutated = false
    init(url: URL, size: Int = 16384) {
        self.url = url
        self.size = size
    }
    func mutateOnce() {
        guard !mutated else { return }
        mutated = true
        try? Data(repeating: 2, count: size).write(to: url)
    }
}
