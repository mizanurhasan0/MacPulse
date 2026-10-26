import Foundation

/// Serializes awaited callbacks without blocking a thread. Concurrent readers can
/// report cumulative byte counters without publishing stale totals or filenames.
actor ScanProgressReporter {
    private var state: FileDiscoveryProgress
    private let callback: @Sendable (FileDiscoveryProgress) async -> Void
    private var sending = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(initial: FileDiscoveryProgress, callback: @Sendable @escaping (FileDiscoveryProgress) async -> Void) {
        state = initial
        self.callback = callback
    }

    func phase(_ stage: FileDiscoveryStage, candidates: Int = 0, bytes: UInt64 = 0, skipped: Int, workers: Int) async {
        state = FileDiscoveryProgress(
            stage: stage, scannedCount: state.scannedCount, hashedBytes: state.hashedBytes,
            skippedCount: skipped, totalHashBytes: bytes, candidateFiles: candidates,
            verifiedBytes: state.verifiedBytes, stoppedAtLimit: state.stoppedAtLimit,
            reusedHashBytes: state.reusedHashBytes, reusedFingerprints: state.reusedFingerprints,
            workerLimit: workers)
        await publish()
    }

    func file(_ name: String) async {
        state.currentFileName = name
        await publish()
    }

    func completed(reusedBytes: UInt64 = 0, reused: Bool = false) async {
        state.completedCandidates += 1
        state.reusedHashBytes += reusedBytes
        if reused { state.reusedFingerprints += 1 }
        await publish()
    }

    func update(_ progress: FileDiscoveryProgress) async {
        state.hashedBytes = max(state.hashedBytes, progress.hashedBytes)
        state.verifiedBytes = max(state.verifiedBytes, progress.verifiedBytes)
        if let name = progress.currentFileName { state.currentFileName = name }
        await publish()
    }

    var snapshot: FileDiscoveryProgress { state }

    private func publish() async {
        let update = state
        if sending {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            sending = true
        }
        if !Task.isCancelled { await callback(update) }
        if waiters.isEmpty { sending = false } else { waiters.removeFirst().resume() }
    }
}
