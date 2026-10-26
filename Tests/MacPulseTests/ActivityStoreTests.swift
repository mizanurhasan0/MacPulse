import XCTest
@testable import MacPulse

final class ActivityStoreTests: XCTestCase {
    func testActivityRecordsRoundTripWithoutPathsOrApplicationNames() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActivityStore(defaults: defaults, storageKey: "history")
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let scan = store.recordCacheScan(folderCount: 4, estimatedBytes: 8192,
                                         isComplete: false, date: date)
        let quit = store.recordGracefulQuit(requestAccepted: true, date: date.addingTimeInterval(1))

        let restored = ActivityStore(defaults: defaults, storageKey: "history").records
        XCTAssertEqual(restored.map(\.id), [quit.id, scan.id])
        XCTAssertEqual(restored[1].status, .partial)
        XCTAssertEqual(restored[1].count, 4)
        XCTAssertEqual(restored[1].estimatedBytes, 8192)
        XCTAssertEqual(restored[0].status, .requested)
        XCTAssertEqual(restored[0].estimatedBytes, nil)
        XCTAssertEqual(restored[0].safeSummary, "Graceful quit request sent")

        let persisted = try XCTUnwrap(defaults.data(forKey: "history"))
        let payload = try XCTUnwrap(String(data: persisted, encoding: .utf8))
        XCTAssertFalse(payload.contains("/Users/"))
        XCTAssertFalse(payload.contains("MacPulse.app"))
    }

    func testRetentionKeepsNewestEntriesAndClearRemovesHistory() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActivityStore(defaults: defaults, storageKey: "history", retentionLimit: 3)

        for index in 0..<5 {
            store.recordCacheScan(folderCount: index, estimatedBytes: UInt64(index),
                                  isComplete: true,
                                  date: Date(timeIntervalSince1970: TimeInterval(index)))
        }

        XCTAssertEqual(store.records.count, 3)
        XCTAssertEqual(store.records.map(\.count), [4, 3, 2])
        store.clearHistory()
        XCTAssertTrue(store.records.isEmpty)
    }

    func testNegativeCountsAreClampedAndQuitRejectionIsRecorded() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = ActivityStore(defaults: defaults, storageKey: "history")

        let scan = store.recordCacheScan(folderCount: -3, estimatedBytes: 0, isComplete: true)
        let quit = store.recordGracefulQuit(requestAccepted: false)

        XCTAssertEqual(scan.count, 0)
        XCTAssertEqual(quit.status, .notAccepted)
        XCTAssertEqual(quit.safeSummary, "Graceful quit request was not accepted")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "MacPulse.ActivityStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
