import AppKit
import Combine
import Foundation

enum CleanerStage: Equatable {
    case idle, scanning, cleaning
}

@MainActor final class CleanerModel: ObservableObject {
    @Published private(set) var snapshot: CleanerSnapshot?
    @Published private(set) var stage: CleanerStage = .idle
    @Published private(set) var entries: [CleanupEntry] = []
    @Published private(set) var logLines: [CleanupLogLine] = []
    @Published private(set) var activityRecords: [ActivityRecord]
    @Published private(set) var lastResult: String?
    @Published private(set) var lastError: String?
    @Published private(set) var hasScanResult = false
    @Published private(set) var isPaused = false
    @Published private(set) var cleanupTotal = 0
    @Published private(set) var cleanupCompletedCount = 0
    @Published private(set) var estimatedCleanedBytes: UInt64 = 0

    private let metrics = LiveSystemMetricsProvider()
    private let cleaner = NativeCleanerService()
    private let activityStore: ActivityStore
    private var monitorTask: Task<Void, Never>?
    private var pauseGate: CleanerPauseGate?
    private var beforeAvailableBytes: UInt64?

    var isBusy: Bool { stage != .idle }
    var cleanupProgress: Double {
        guard cleanupTotal > 0 else { return 0 }
        return min(1, Double(cleanupCompletedCount) / Double(cleanupTotal))
    }
    var cleanupIsComplete: Bool { cleanupTotal > 0 && cleanupCompletedCount >= cleanupTotal && stage == .idle }
    var areAllEntriesSelected: Bool { !entries.isEmpty && entries.allSatisfy(\.isSelected) }
    var selectedCount: Int { entries.filter { $0.isSelected && $0.state == .pending }.count }
    var displayedSelectedCount: Int {
        stage == .cleaning || cleanupIsComplete ? cleanupTotal : selectedCount
    }
    var selectedBytes: UInt64 {
        entries.filter { $0.isSelected && $0.state == .pending }
            .reduce(UInt64(0)) { $0 &+ $1.estimatedBytes }
    }
    var pendingCount: Int { entries.filter { $0.state == .pending }.count }
    var skippedCount: Int { entries.filter { $0.state == .retained }.count }

    func isCategorySelected(_ category: String) -> Bool {
        let items = entries.filter { $0.category == category }
        return !items.isEmpty && items.allSatisfy(\.isSelected)
    }

    func setEntry(_ path: String, selected: Bool) {
        guard let index = entries.firstIndex(where: { $0.url.path == path }),
              entries[index].state == .pending else { return }
        entries[index].isSelected = selected
    }

    var confirmationSummary: String {
        let selected = entries.filter { $0.isSelected && $0.state == .pending }
        let grouped = Dictionary(grouping: selected, by: \.category).sorted { $0.key < $1.key }
        let folders = selected.prefix(12).map { "• \($0.url.lastPathComponent)" }.joined(separator: "\n")
        let remaining = selected.count > 12 ? "\n… and \(selected.count - 12) more folders" : ""
        let categories = grouped.map { "\($0.key): \($0.value.count)" }.joined(separator: " · ")
        return "\(selected.count) folders · \(ByteCountFormatter.string(fromByteCount: Int64(clamping: selected.reduce(UInt64(0)) { $0 &+ $1.estimatedBytes }), countStyle: .file))\n\(categories)\n\n\(folders)\(remaining)"
    }

    init(activityStore: ActivityStore = ActivityStore()) {
        self.activityStore = activityStore
        activityRecords = activityStore.records
    }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMetrics()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func refreshMetrics() async {
        snapshot = metrics.snapshot()
    }

    func clearHistory() {
        activityStore.clearHistory()
        activityRecords = []
    }

    func clearError() {
        lastError = nil
    }

    func scanForCleanup() {
        guard !isBusy else { return }
        lastError = nil
        lastResult = nil
        hasScanResult = false
        cleanupTotal = 0
        cleanupCompletedCount = 0
        estimatedCleanedBytes = 0
        entries = []
        logLines = []
        beforeAvailableBytes = snapshot?.availableStorageBytes
        isPaused = false
        pauseGate = CleanerPauseGate()
        stage = .scanning
        appendLog("Scanning eligible cache, browser, log, and developer folders…")
        Task { await performScan() }
    }

    func togglePauseResume() {
        guard isBusy, let pauseGate else { return }
        if isPaused {
            pauseGate.resume()
            isPaused = false
            appendLog("Resumed \(stage == .scanning ? "scan" : "cleanup")")
        } else {
            pauseGate.pause()
            isPaused = true
            appendLog("Paused \(stage == .scanning ? "scan" : "cleanup")")
        }
    }

    func selectAll(_ selected: Bool) {
        for index in entries.indices where entries[index].state == .pending {
            entries[index].isSelected = selected
        }
    }

    func selectCategory(_ category: String, selected: Bool) {
        for index in entries.indices
        where entries[index].category == category && entries[index].state == .pending {
            entries[index].isSelected = selected
        }
    }

    func cleanSelected() {
        guard !isBusy else { return }
        let plan = entries.filter { $0.isSelected && $0.state == .pending }
        guard !plan.isEmpty else {
            lastError = "Select at least one folder to clean."
            return
        }
        lastError = nil
        cleanupTotal = plan.count
        cleanupCompletedCount = 0
        estimatedCleanedBytes = 0
        isPaused = false
        pauseGate = CleanerPauseGate()
        stage = .cleaning
        appendLog("Removing \(plan.count) selected folders…")
        Task { await performCleanup(plan) }
    }

    private func performScan() async {
        guard let pauseGate else { return }
        let plan = await cleaner.scan(pauseGate: pauseGate) { [weak self] category in
            Task { @MainActor [weak self] in self?.appendLog("Scanning · \(category)") }
        }
        entries = plan
        hasScanResult = true
        guard !plan.isEmpty else {
            lastResult = "No eligible cleanup items were found."
            appendLog(lastResult ?? "No cleanup items")
            await refreshMetrics()
            record(status: .completed, count: 0)
            stage = .idle
            isPaused = false
            self.pauseGate = nil
            return
        }
        lastResult = "Scan complete · \(plan.count) folders ready for review"
        appendLog(lastResult ?? "Scan complete")
        stage = .idle
        isPaused = false
        self.pauseGate = nil
    }

    private func performCleanup(_ plan: [CleanupEntry]) async {
        guard let pauseGate else { return }
        let runningBundleIDs = Set(
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).map { $0.lowercased() })
        let results = await cleaner.clean(plan, runningBundleIDs: runningBundleIDs, pauseGate: pauseGate) { [weak self] path, state in
            Task { @MainActor [weak self] in
                guard let self, let index = self.entries.firstIndex(where: { $0.url.path == path }) else { return }
                let previousState = self.entries[index].state
                self.entries[index].state = state
                if state == .removed || state == .retained,
                   previousState == .pending || previousState == .cleaning {
                    self.cleanupCompletedCount += 1
                    if state == .removed {
                        self.estimatedCleanedBytes &+= self.entries[index].estimatedBytes
                    }
                }
                if state == .cleaning {
                    self.appendLog("Cleaning: \(path)")
                } else {
                    let removed = state == .removed
                    self.appendLog("\(removed ? "Removed" : "Skipped"): \(path)", warning: !removed)
                }
            }
        }
        let resultsByPath = Dictionary(uniqueKeysWithValues: results.map { ($0.url.path, $0) })
        for index in entries.indices {
            if let result = resultsByPath[entries[index].url.path] {
                entries[index].state = result.state
            }
        }
        cleanupCompletedCount = results.count
        estimatedCleanedBytes = results
            .filter { $0.state == .removed }
            .reduce(UInt64(0)) { $0 &+ $1.estimatedBytes }
        await refreshMetrics()

        let removedCount = results.filter { $0.state == .removed }.count
        let retainedCount = results.count - removedCount
        let status: ActivityStatus = retainedCount == 0 ? .completed : .partial
        lastResult = "Cleanup finished · \(removedCount) removed · \(retainedCount) skipped"
        appendLog(lastResult ?? "Cleanup finished")
        record(status: status, count: removedCount)
        stage = .idle
        isPaused = false
        self.pauseGate = nil
    }

    private func record(status: ActivityStatus, count: Int) {
        let after = snapshot?.availableStorageBytes
        let delta: Int64? = if let beforeAvailableBytes, let after {
            Int64(clamping: after) - Int64(clamping: beforeAvailableBytes)
        } else {
            nil
        }
        _ = activityStore.recordOperation(
            kind: .cleanerCleanup, status: status, count: count, availableStorageDelta: delta)
        activityRecords = activityStore.records
    }

    private func appendLog(_ text: String, warning: Bool = false) {
        logLines.append(CleanupLogLine(text: text, isWarning: warning))
        if logLines.count > 500 { logLines.removeFirst(logLines.count - 500) }
    }
}
