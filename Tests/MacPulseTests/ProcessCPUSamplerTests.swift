import XCTest
@testable import MacPulse

final class ProcessCPUSamplerTests: XCTestCase {
    func testUsesNanosecondIntervalAndAllowsMoreThanOneCore() {
        var sampler = ProcessCPUSampler()
        XCTAssertNil(sample(&sampler, time: 1_000_000_000, cpu: 100))
        let value = sampler.sample(pid: 10, executablePath: "/Applications/Editor.app/Editor",
                                   processStartTime: 1, userNanoseconds: 1_000_000_100,
                                   systemNanoseconds: 1_500_000_000,
                                   sampledAtNanoseconds: 2_000_000_000)
        XCTAssertEqual(value ?? -1, 250, accuracy: 0.001)
    }

    func testReusedPIDAndChangedExecutableDoNotReuseOldCounter() {
        var sampler = ProcessCPUSampler()
        XCTAssertNil(sample(&sampler, time: 1_000_000_000, cpu: 100))
        XCTAssertNil(sample(&sampler, time: 2_000_000_000, cpu: 2_000_000_000, start: 2))
        XCTAssertEqual(sample(&sampler, time: 3_000_000_000, cpu: 3_000_000_000, start: 2) ?? -1, 100, accuracy: 0.001)
        XCTAssertNil(sample(&sampler, time: 4_000_000_000, cpu: 4_000_000_000, start: 2, path: "/Applications/Other.app/Other"))
    }

    func testCounterResetAndNonIncreasingClockAreUnavailable() {
        var sampler = ProcessCPUSampler()
        XCTAssertNil(sample(&sampler, time: 1_000_000_000, cpu: 4_000_000_000))
        XCTAssertNil(sample(&sampler, time: 2_000_000_000, cpu: 1_000_000_000))
        XCTAssertNil(sample(&sampler, time: 2_000_000_000, cpu: 2_000_000_000))
        XCTAssertEqual(sample(&sampler, time: 3_000_000_000, cpu: 3_000_000_000) ?? -1, 100, accuracy: 0.001)
    }

    func testVeryShortRefreshPreservesUsefulOlderSample() {
        var sampler = ProcessCPUSampler()
        XCTAssertNil(sample(&sampler, time: 1_000_000_000, cpu: 0))
        XCTAssertNil(sample(&sampler, time: 1_001_000_000, cpu: 40_000_000))
        XCTAssertEqual(sample(&sampler, time: 2_000_000_000, cpu: 500_000_000) ?? -1, 50, accuracy: 0.001)
    }

    func testUnknownIdentityAndEvictedPIDsStartWithNoRate() {
        var sampler = ProcessCPUSampler()
        XCTAssertNil(sample(&sampler, time: 1_000_000_000, cpu: 0))
        XCTAssertNil(sample(&sampler, time: 2_000_000_000, cpu: 1_000_000_000, path: nil))
        XCTAssertNil(sample(&sampler, time: 3_000_000_000, cpu: 2_000_000_000))
        sampler.retain(pids: [])
        XCTAssertNil(sample(&sampler, time: 4_000_000_000, cpu: 3_000_000_000))
    }

    func testOverflowingCountersAreUnavailable() {
        var sampler = ProcessCPUSampler()
        XCTAssertNil(sampler.sample(pid: 10, executablePath: "/App", processStartTime: 1,
                                    userNanoseconds: .max, systemNanoseconds: 1,
                                    sampledAtNanoseconds: 1_000_000_000))
    }

    private func sample(_ sampler: inout ProcessCPUSampler, time: UInt64, cpu: UInt64,
                        start: UInt64 = 1, path: String? = "/Applications/Editor.app/Editor") -> Double? {
        sampler.sample(pid: 10, executablePath: path, processStartTime: start,
                       userNanoseconds: cpu, systemNanoseconds: 0, sampledAtNanoseconds: time)
    }
}
