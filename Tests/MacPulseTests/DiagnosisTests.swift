import XCTest
@testable import MacPulse

final class DiagnosisTests: XCTestCase {
    func testHealthySnapshotHasNoFindings() {
        let findings = DiagnosisEngine().findings(for: snapshot(available: 0.5, cpu: 20, pressure: .healthy, thermal: .nominal))
        XCTAssertTrue(findings.isEmpty)
    }

    func testLowStorageIsPrioritizedAsCritical() {
        let findings = DiagnosisEngine().findings(for: snapshot(available: 0.02, cpu: 15, pressure: .healthy, thermal: .nominal))
        XCTAssertEqual(findings.first?.id, "storage-low")
        XCTAssertEqual(findings.first?.severity, .critical)
    }

    func testDiagnosisThresholdsCanBeConfigured() {
        var thresholds = DiagnosisThresholds()
        thresholds.lowStorageAttentionFraction = 0.20
        thresholds.lowStorageCriticalFraction = 0.10
        let reading = snapshot(available: 0.15, cpu: 15, pressure: .healthy, thermal: .nominal)
        let finding = DiagnosisEngine(thresholds: thresholds).findings(for: reading).first
        XCTAssertEqual(finding?.severity, .attention)
        XCTAssertEqual(finding?.risk, .reviewRequired)
        XCTAssertEqual(finding?.confidence, .high)
        XCTAssertFalse(finding?.possibleCauses.isEmpty ?? true)
    }

    func testElevatedMemoryAndThermalAreReported() {
        let findings = DiagnosisEngine().findings(for: snapshot(available: 0.5, cpu: 10, pressure: .attention, thermal: .serious))
        XCTAssertEqual(Set(findings.map(\.id)), ["memory-pressure", "thermal-elevated"])
    }

    func testHighCPUSingleSampleDoesNotTriggerFinding() {
        let highCPU = snapshot(available: 0.5, cpu: 95, pressure: .healthy, thermal: .nominal)
        XCTAssertFalse(DiagnosisEngine().findings(for: highCPU).contains { $0.id == "cpu-busy" })
        XCTAssertTrue(DiagnosisEngine().findings(for: highCPU, sustainedCPU: true).contains { $0.id == "cpu-busy" })
    }

    func testCPUDeltaUsesAllCategoriesAndHandlesCounterWrap() {
        let reading = CPUReading.interval(current: [20, 40, 10, 30], previous: [10, 20, 10, 10])
        XCTAssertEqual(reading?.total ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(reading?.user ?? -1, 20, accuracy: 0.001)
        XCTAssertEqual(reading?.system ?? -1, 80, accuracy: 0.001)

        let wrapped = CPUReading.interval(current: [1, 0, 0, 0], previous: [UInt32.max, 0, 0, 0])
        XCTAssertEqual(wrapped?.user, 100)
        XCTAssertEqual(wrapped?.total, 100)
    }

    func testProcessProtectionDefaultsToDenyForCoreAndUnknownIdentity() {
        let windowServer = ProcessReading(pid: 40, name: "WindowServer", bundleIdentifier: "com.apple.WindowServer", memoryBytes: 1, cpuPercent: nil)
        let unknown = ProcessReading(pid: 42, name: "Unknown", bundleIdentifier: nil, memoryBytes: 1, cpuPercent: nil)
        let ordinaryApp = ProcessReading(pid: 43, name: "Editor", bundleIdentifier: "com.example.Editor", memoryBytes: 1, cpuPercent: nil)
        let systemPathApp = ProcessReading(pid: 44, name: "Daemon", bundleIdentifier: "org.example.Daemon", memoryBytes: 1, cpuPercent: nil, executablePath: "/System/Library/CoreServices/Daemon")
        XCTAssertTrue(ProcessProtectionPolicy.isProtected(windowServer, ownBundleIdentifier: "com.example.MacPulse"))
        XCTAssertTrue(ProcessProtectionPolicy.isProtected(unknown, ownBundleIdentifier: "com.example.MacPulse"))
        XCTAssertFalse(ProcessProtectionPolicy.isProtected(ordinaryApp, ownBundleIdentifier: "com.example.MacPulse"))
        XCTAssertTrue(ProcessProtectionPolicy.isProtected(systemPathApp, ownBundleIdentifier: "com.example.MacPulse"))
    }

    private func snapshot(available: Double, cpu: Double, pressure: HealthState, thermal: ProcessInfo.ThermalState) -> PerformanceSnapshot {
        PerformanceSnapshot(timestamp: .now,
            cpu: CPUReading(total: cpu, user: cpu / 2, system: cpu / 2, idle: 100 - cpu, isAvailable: true),
            memory: MemoryReading(physicalBytes: 16_000_000_000, appBytes: 0, wiredBytes: 0, compressedBytes: 0, swapUsedBytes: nil, pressure: pressure),
            storage: StorageReading(totalBytes: 1_000_000, availableBytes: UInt64(available * 1_000_000)),
            thermal: ThermalReading(state: thermal, health: thermal == .nominal ? .healthy : .attention),
            processes: [])
    }
}
