import Foundation

/// Interval CPU accounting. 100% means one fully occupied CPU core, matching Activity Monitor.
/// A process with several busy threads can therefore exceed 100%.
struct ProcessCPUSampler: Sendable {
    private struct Counter: Sendable {
        var executablePath: String
        var processStartTime: UInt64
        var cumulativeNanoseconds: UInt64
        var sampledAtNanoseconds: UInt64
    }

    private var counters: [Int32: Counter] = [:]
    private static let minimumIntervalNanoseconds: UInt64 = 50_000_000

    mutating func sample(pid: Int32, executablePath: String?, processStartTime: UInt64,
                         userNanoseconds: UInt64, systemNanoseconds: UInt64,
                         sampledAtNanoseconds: UInt64) -> Double? {
        guard pid > 0, let executablePath, !executablePath.isEmpty, processStartTime > 0 else {
            counters.removeValue(forKey: pid)
            return nil
        }
        let (total, overflow) = userNanoseconds.addingReportingOverflow(systemNanoseconds)
        guard !overflow else {
            counters.removeValue(forKey: pid)
            return nil
        }
        let current = Counter(executablePath: executablePath, processStartTime: processStartTime,
                              cumulativeNanoseconds: total, sampledAtNanoseconds: sampledAtNanoseconds)
        guard let previous = counters[pid],
              previous.executablePath == executablePath,
              previous.processStartTime == processStartTime,
              sampledAtNanoseconds > previous.sampledAtNanoseconds,
              total >= previous.cumulativeNanoseconds else {
            counters[pid] = current
            return nil
        }
        let elapsed = sampledAtNanoseconds - previous.sampledAtNanoseconds
        // Preserve the older sample when manual refreshes are too close together.
        guard elapsed >= Self.minimumIntervalNanoseconds else { return nil }
        counters[pid] = current
        let result = Double(total - previous.cumulativeNanoseconds) / Double(elapsed) * 100
        return result.isFinite && result >= 0 ? result : nil
    }

    mutating func retain(pids: Set<Int32>) {
        counters = counters.filter { pids.contains($0.key) }
    }

    mutating func discard(pid: Int32) {
        counters.removeValue(forKey: pid)
    }
}
