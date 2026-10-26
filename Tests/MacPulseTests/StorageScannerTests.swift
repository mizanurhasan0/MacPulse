import XCTest
@testable import MacPulse

final class StorageScannerTests: XCTestCase {
    func testScannerDoesNotFollowSymlinkedFiles() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let cache = fixture.appendingPathComponent("AppCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let visibleFile = cache.appendingPathComponent("ordinary.data")
        try Data(repeating: 1, count: 4096).write(to: visibleFile)
        let externalFile = fixture.appendingPathComponent("outside.data")
        try Data(repeating: 2, count: 1_000_000).write(to: externalFile)
        try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("linked.data"), withDestinationURL: externalFile)

        let result = try await SafeStorageScanner().scan(root: fixture)
        XCTAssertEqual(result.count, 1)
        XCTAssertLessThan(result[0].logicalBytes, 100_000, "The scanner must size the regular fixture file, not follow the much larger symlink target.")
    }

    func testScannerCountsHardLinkedFileOnlyOnce() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let cache = fixture.appendingPathComponent("AppCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let original = cache.appendingPathComponent("data.bin")
        let alias = cache.appendingPathComponent("data-alias.bin")
        try Data(repeating: 7, count: 256 * 1024).write(to: original)
        try FileManager.default.linkItem(at: original, to: alias)

        let result = try await SafeStorageScanner().scan(root: fixture)
        XCTAssertEqual(result.count, 1)
        XCTAssertLessThan(result[0].logicalBytes, 400 * 1024, "A hard link must not double-count the same file's allocated blocks.")
    }

    func testPreCancelledScanThrowsCancellation() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let cache = fixture.appendingPathComponent("AppCache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 4096).write(to: cache.appendingPathComponent("file"))

        let task = Task { try await SafeStorageScanner().scan(root: fixture) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled scan should throw CancellationError.")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testScannerRejectsSymlinkedRoot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let realDirectory = fixture.appendingPathComponent("real", isDirectory: true)
        let linkedDirectory = fixture.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedDirectory, withDestinationURL: realDirectory)
        do {
            _ = try await SafeStorageScanner().scan(root: linkedDirectory)
            XCTFail("A symlinked scan root must be rejected.")
        } catch StorageScanError.invalidRoot {
            // Expected.
        }
    }

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacPulseScanner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
