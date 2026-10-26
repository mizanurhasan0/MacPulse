import Foundation

struct ScanSystemState: Sendable {
    var processorCount: Int
    var lowPowerMode: Bool
    var thermalState: ProcessInfo.ThermalState

    static func current() -> ScanSystemState {
        let process = ProcessInfo.processInfo
        return ScanSystemState(processorCount: process.activeProcessorCount,
                               lowPowerMode: process.isLowPowerModeEnabled,
                               thermalState: process.thermalState)
    }
}

struct ScanVolumeInfo: Sendable {
    var isLocal: Bool
    var isInternal: Bool
    var isRemovable: Bool

    static func read(_ root: URL) -> ScanVolumeInfo {
        let values = try? root.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRemovableKey])
        return ScanVolumeInfo(isLocal: values?.volumeIsLocal == true,
                              isInternal: values?.volumeIsInternal == true,
                              isRemovable: values?.volumeIsRemovable != false)
    }

    var permitsFingerprintReuse: Bool { isLocal && isInternal && !isRemovable }
}

struct ScanWorkerPolicy: Sendable {
    let maximumWorkers: Int
    var adaptive = true

    init(maximumWorkers: Int = 2, adaptive: Bool = true) {
        self.maximumWorkers = min(4, max(1, maximumWorkers))
        self.adaptive = adaptive
    }

    func limit(system: ScanSystemState, volume: ScanVolumeInfo) -> Int {
        guard adaptive else { return maximumWorkers }
        guard system.processorCount >= 4, volume.isLocal, volume.isInternal,
              !volume.isRemovable, !system.lowPowerMode else { return 1 }
        switch system.thermalState {
        case .serious, .critical: return 1
        case .fair: return min(2, maximumWorkers)
        case .nominal: return min(maximumWorkers, max(1, system.processorCount / 2))
        @unknown default: return 1
        }
    }
}

/// Only a bounded number of child tasks exist at once. Reductions in the limit take
/// effect as in-flight files finish; no thread waits on a semaphore.
enum BoundedScanWork {
    static func map<Input: Sendable, Output: Sendable>(
        _ inputs: [Input], limit: @Sendable @escaping () -> Int,
        operation: @Sendable @escaping (Input) async throws -> Output
    ) async throws -> [Output] {
        guard !inputs.isEmpty else { return [] }
        return try await withThrowingTaskGroup(of: (Int, Output).self) { group in
            var results: [Output?] = Array(repeating: nil, count: inputs.count)
            var nextIndex = 0
            var inFlight = 0
            while nextIndex < inputs.count || inFlight > 0 {
                try Task.checkCancellation()
                let capacity = min(4, max(1, limit()))
                while nextIndex < inputs.count && inFlight < capacity {
                    let index = nextIndex
                    let input = inputs[index]
                    group.addTask(priority: .utility) { (index, try await operation(input)) }
                    nextIndex += 1
                    inFlight += 1
                }
                guard let (index, result) = try await group.next() else { break }
                results[index] = result
                inFlight -= 1
            }
            try Task.checkCancellation()
            return results.compactMap { $0 }
        }
    }
}
