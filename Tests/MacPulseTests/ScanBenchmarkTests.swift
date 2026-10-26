import Foundation
import XCTest

@testable import MacPulse

/// Opt-in generated data only. Clear the application's fingerprint cache for each
/// cold sample; OS filesystem caches remain warm and are explicitly not flushed.
@MainActor final class ScanBenchmarkTests: XCTestCase {
    func testGeneratedScannerBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["MACPULSE_SCAN_BENCHMARK"] == "1" else {
            throw XCTSkip("Set MACPULSE_SCAN_BENCHMARK=1 for the generated-data benchmark")
        }
        let root = FilePathPolicy.normalized(FileManager.default.temporaryDirectory)
            .appendingPathComponent("MacPulseBenchmark-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        print("BENCHMARK_OS \(ProcessInfo.processInfo.operatingSystemVersionString) cores=\(ProcessInfo.processInfo.activeProcessorCount)")
        for (label, count, size, copies) in [
            ("small", 256, 64 * 1024, 4),
            ("medium", 64, 4 * 1024 * 1024, 4),
            ("large", 8, 32 * 1024 * 1024, 2),
            ("unique", 128, 1024 * 1024, 1),
        ] {
            let folder = root.appendingPathComponent(label, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for index in 0..<count {
                let data = Data(repeating: UInt8(index / copies), count: size)
                try data.write(to: folder.appendingPathComponent(String(format: "%04d.bin", index)))
            }
            var durations: [Int: [Double]] = [:]
            // Rotate order to reduce a consistent first-run filesystem-cache bias.
            for order in [[1, 2, 4], [4, 1, 2], [2, 4, 1]] {
                for workers in order {
                    let scanner = scanner(workers: workers)
                    let start = ContinuousClock().now
                    let result = try await scanner.scan(root: folder)
                    let elapsed = start.duration(to: ContinuousClock().now)
                    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                    durations[workers, default: []].append(seconds)
                    XCTAssertEqual(result.scannedCount, count)
                    XCTAssertEqual(result.duplicateGroups.count, copies > 1 ? count / copies : 0)
                    XCTAssertTrue(result.isComplete)
                }
            }
            for workers in [1, 2, 4] {
                let sorted = durations[workers]!.sorted()
                print(String(format: "BENCHMARK %@ workers=%d files=%d bytes=%d median=%.4f range=%.4f...%.4f",
                    label, workers, count, count * size, sorted[1], sorted[0], sorted[2]))
            }
            let cachedScanner = scanner(workers: 2)
            let cold = try await cachedScanner.scan(root: folder)
            let start = ContinuousClock().now
            let warm = try await cachedScanner.scan(root: folder)
            let elapsed = start.duration(to: ContinuousClock().now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            XCTAssertEqual(warm.duplicateGroups.map(\.id), cold.duplicateGroups.map(\.id))
            XCTAssertEqual(warm.statistics.hashedBytes, 0)
            XCTAssertEqual(warm.statistics.verifiedBytes, cold.statistics.verifiedBytes)
            print(String(format: "BENCHMARK_WARM %@ seconds=%.4f hashRead=%llu hashReused=%llu verifyRead=%llu",
                label, seconds, warm.statistics.hashedBytes, warm.statistics.reusedHashBytes, warm.statistics.verifiedBytes))
            try FileManager.default.removeItem(at: folder)
        }
    }

    private func scanner(workers: Int) -> FileDiscoveryService {
        FileDiscoveryService(workerPolicy: ScanWorkerPolicy(maximumWorkers: workers, adaptive: false),
            volumeInfo: { _ in ScanVolumeInfo(isLocal: true, isInternal: true, isRemovable: false) })
    }
}
