import AppKit
import Combine
import Foundation

enum WorkspaceOperation: Equatable { case idle, cacheScan, fileScan, boostScan, applying }
enum BoostStage: Equatable { case scanning, review, executing, results, failed }

struct BoostPlan {
    var measurement: PerformanceMeasurement
    var findings: [Finding]
    var applications: [ProcessReading]
    var caches: [CleanupCandidate]
}

struct CleanupReview: Identifiable {
    var id = UUID()
    var actions: [PlannedAction]
    var source: ActivityKind
    var estimatedBytes: UInt64 { actions.reduce(0) { $0 + $1.estimatedBytes } }
}

struct MetricHistoryPoint: Identifiable {
    var id: Date { date }
    var date: Date
    var cpu: Double?
    var availableMemory: Double?
}

@MainActor final class DashboardModel: ObservableObject {
    @Published private(set) var snapshot: PerformanceSnapshot?
    @Published private(set) var findings: [Finding] = []
    @Published private(set) var metricHistory: [MetricHistoryPoint] = []
    @Published private(set) var cacheCandidates: [CleanupCandidate] = []
    @Published private(set) var cacheScanCompleted = false
    @Published private(set) var operation: WorkspaceOperation = .idle
    @Published private(set) var fileResult: FileDiscoveryResult?
    @Published private(set) var fileScanProgress: FileDiscoveryProgress?
    @Published private(set) var activeFileScanMode: FileDiscoveryMode?
    @Published private(set) var scanRoot: URL?
    @Published var minimumLargeFileMiB = 100
    @Published private(set) var reuseScanFingerprints = true
    @Published var selectedCaches = Set<URL>()
    @Published var selectedLargeFiles = Set<URL>()
    @Published var selectedDuplicates = Set<URL>()
    @Published private(set) var duplicateKeepers: [String: URL] = [:]
    @Published var pendingReview: CleanupReview?
    @Published var presentedReport: ActionReport?
    @Published var workflowError: String?
    @Published var workflowNotice: WorkflowKey?
    @Published private(set) var executionProgress: ExecutionProgress?
    @Published var isBoostPresented = false
    @Published private(set) var boostStage: BoostStage = .scanning
    @Published private(set) var boostScanMessage: WorkflowKey = .verifyBefore
    @Published private(set) var boostPlan: BoostPlan?
    @Published private(set) var boostReport: ActionReport?
    @Published var boostSelectedApps = Set<Int32>()
    @Published var boostSelectedCaches = Set<URL>()
    @Published private(set) var lastError: String?
    @Published var selectedSection = "Dashboard"
    @Published var storageMode = 0
    @Published var selectedProcess: ProcessReading?
    @Published var processActionMessage: String?
    @Published private(set) var activityRecords: [ActivityRecord]
    @Published private(set) var monitoringEnabled =
        UserDefaults.standard.object(forKey: "monitoringEnabled") as? Bool ?? true
    @Published private(set) var monitoringInterval =
        UserDefaults.standard.object(forKey: "monitoringInterval") as? Double ?? 3.0

    private let provider: any SystemMetricsProvider
    private let diagnosis = DiagnosisEngine()
    private let scanner = SafeStorageScanner()
    private let fileScanner = FileDiscoveryService()
    private let executor: ActionExecutor
    private let activityStore: ActivityStore
    private let cacheRoot: URL
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var highCPUSampleCount = 0
    private var scopedRoot: URL?
    private var snoozed: [String: Date]

    var isScanning: Bool { operation == .cacheScan }
    var isBusy: Bool { operation != .idle }
    var runningBundleIDs: Set<String> {
        Set(
            snapshot?.processes.compactMap(\.bundleIdentifier)
                ?? NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    init(
        provider: any SystemMetricsProvider = LiveSystemMetricsProvider(),
        cacheRoot: URL = CacheProtectionPolicy.defaultRoot, executor: ActionExecutor? = nil,
        activityStore: ActivityStore = ActivityStore(), defaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.cacheRoot = cacheRoot
        self.executor = executor ?? ActionExecutor(trashService: TrashService(cacheRoot: cacheRoot))
        self.activityStore = activityStore
        self.defaults = defaults
        self.snoozed = defaults.dictionary(forKey: "macpulse.snoozed") as? [String: Date] ?? [:]
        activityRecords = activityStore.records
        monitoringEnabled = defaults.object(forKey: "monitoringEnabled") as? Bool ?? true
        monitoringInterval = defaults.object(forKey: "monitoringInterval") as? Double ?? 3.0
        minimumLargeFileMiB = defaults.object(forKey: "macpulse.largeThreshold") as? Int ?? 100
        reuseScanFingerprints = defaults.object(forKey: "macpulse.reuseScanFingerprints") as? Bool ?? true
    }

    func recordGracefulQuit(requestAccepted: Bool) {
        _ = activityStore.recordGracefulQuit(requestAccepted: requestAccepted)
        activityRecords = activityStore.records
    }

    func clearActivityHistory() {
        activityStore.clearHistory()
        activityRecords = []
    }

    func startMonitoring() {
        guard refreshTask == nil, monitoringEnabled else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                let thermalMultiplier = snapshot?.thermal.health == .critical ? 3.0 : 1.0
                try? await Task.sleep(for: .seconds(monitoringInterval * thermalMultiplier))
            }
        }
    }

    func updateMonitoringSettings(enabled: Bool, interval: Double) {
        monitoringEnabled = enabled
        monitoringInterval = min(5, max(2, interval))
        defaults.set(enabled, forKey: "monitoringEnabled")
        defaults.set(monitoringInterval, forKey: "monitoringInterval")
        stopMonitoring()
        startMonitoring()
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        do {
            let next = try await provider.snapshot()
            snapshot = next
            metricHistory.append(
                MetricHistoryPoint(
                    date: next.timestamp, cpu: next.cpu.isAvailable ? next.cpu.total : nil,
                    availableMemory: next.memory.estimatedAvailableFraction.map { $0 * 100 }))
            if metricHistory.count > 60 { metricHistory.removeFirst(metricHistory.count - 60) }
            if next.cpu.isAvailable && next.cpu.total >= 85 {
                highCPUSampleCount += 1
            } else if next.cpu.total < 75 {
                highCPUSampleCount = 0
            }
            findings = diagnosis.findings(for: next, sustainedCPU: highCPUSampleCount >= 3)
                .filter { snoozed[$0.id, default: .distantPast] < .now }
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }

    func snoozeFinding(_ id: String) {
        snoozed[id] = Date().addingTimeInterval(3600)
        defaults.set(snoozed, forKey: "macpulse.snoozed")
        findings.removeAll { $0.id == id }
        boostPlan?.findings.removeAll { $0.id == id }
    }

    func resetSnoozedFindings() {
        snoozed = [:]
        defaults.removeObject(forKey: "macpulse.snoozed")
        Task { await refresh() }
    }

    func cacheRejection(_ candidate: CleanupCandidate) -> CacheProtectionReason? {
        CacheProtectionPolicy.rejectionReason(
            candidate: candidate, runningBundleIDs: runningBundleIDs, cacheRoot: cacheRoot,
            revalidateIdentity: false)
    }

    func startCacheScan() {
        guard !isBusy else { return }
        operation = .cacheScan
        workflowNotice = nil
        operationTask = Task { [self] in
            defer {
                operation = .idle
                operationTask = nil
            }
            do {
                let result = try await scanner.scan(root: cacheRoot)
                try Task.checkCancellation()
                cacheCandidates = result
                cacheScanCompleted = true
                selectedCaches = []
                recordCacheScan(result)
                workflowNotice = result.isEmpty ? .scanEmpty : .scanFinished
            } catch is CancellationError {
                workflowNotice = .operationCancelled
            } catch { workflowError = error.localizedDescription }
        }
    }

    func scanCaches() async {
        startCacheScan()
        await operationTask?.value
    }

    func cancelOperation() { operationTask?.cancel() }

    func chooseScanFolder() async {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard await panel.begin() == .OK, let url = panel.url else { return }
        acceptScanFolder(url)
    }

    func acceptScanFolder(_ url: URL) {
        guard !isBusy else { return }
        if let scopedRoot { scopedRoot.stopAccessingSecurityScopedResource() }
        scopedRoot = url.startAccessingSecurityScopedResource() ? url : nil
        scanRoot = url
        fileResult = nil
        selectedLargeFiles = []
        selectedDuplicates = []
        duplicateKeepers = [:]
        workflowNotice = nil
    }

    func startFileScan() {
        guard !isBusy, let scanRoot else { return }
        let mode: FileDiscoveryMode = storageMode == 1 ? .largeFiles : .combined
        let throttle = FileScanUIThrottle()
        operation = .fileScan
        activeFileScanMode = mode
        fileScanProgress = nil
        selectedLargeFiles = []
        selectedDuplicates = []
        workflowNotice = nil
        operationTask = Task { [self] in
            defer {
                operation = .idle
                activeFileScanMode = nil
                operationTask = nil
            }
            do {
                let result = try await fileScanner.scan(
                    root: scanRoot,
                    minimumLargeFileBytes: UInt64(max(1, minimumLargeFileMiB)) * 1_048_576,
                    mode: mode, reuseFingerprints: reuseScanFingerprints,
                    enumerated: { [weak self] preliminary in
                        await MainActor.run { self?.fileResult = preliminary }
                    }
                ) { [weak self] progress in
                    if await throttle.shouldPublish(progress.stage) {
                        await MainActor.run { self?.fileScanProgress = progress }
                    }
                }
                try Task.checkCancellation()
                fileResult = result
                selectedLargeFiles = []
                selectedDuplicates = []
                duplicateKeepers = [:]
                _ = activityStore.recordOperation(
                    kind: .fileScan, status: result.isComplete ? .completed : .partial,
                    count: result.scannedCount)
                activityRecords = activityStore.records
                workflowNotice = result.isComplete ? .scanFinished : .scanSkipped
            } catch is CancellationError {
                workflowNotice = fileResult?.duplicatesScanned == false ? .scanCancelledPartial : .operationCancelled
            } catch { workflowError = error.localizedDescription }
        }
    }

    func setReuseScanFingerprints(_ enabled: Bool) async {
        guard !isBusy else { return }
        reuseScanFingerprints = enabled
        defaults.set(enabled, forKey: "macpulse.reuseScanFingerprints")
        if !enabled { await fileScanner.clearFingerprintCache() }
    }

    func clearScanMemory() async {
        guard !isBusy else { return }
        await fileScanner.clearFingerprintCache()
        workflowNotice = .scanMemoryCleared
    }

    private func recordCacheScan(_ result: [CleanupCandidate]) {
        _ = activityStore.recordCacheScan(
            folderCount: result.count,
            estimatedBytes: result.reduce(0) { $0 + $1.allocatedBytes },
            isComplete: result.allSatisfy(\.isComplete))
        activityRecords = activityStore.records
    }

    private func cacheActions(ids: Set<URL>, candidates: [CleanupCandidate]) -> [PlannedAction] {
        let selectedPaths = Set(ids.map { FilePathPolicy.normalized($0).path })
        return candidates.filter {
            selectedPaths.contains(FilePathPolicy.normalized($0.url).path) && cacheRejection($0) == nil
        }.compactMap { candidate in
            return (try? TrashTarget.cache(candidate, root: cacheRoot)).map(PlannedAction.trash)
        }
    }

    func prepareCacheCleanup() {
        let actions = cacheActions(ids: selectedCaches, candidates: cacheCandidates)
        guard !isBusy else { return }
        guard !actions.isEmpty else {
            workflowNotice = .freshScanRequired
            return
        }
        pendingReview = CleanupReview(actions: actions, source: .cacheCleanup)
    }

    func prepareFileCleanup(duplicates: Bool) {
        guard !isBusy, let result = fileResult else { return }
        let actions: [PlannedAction]
        if duplicates {
            actions = result.duplicateGroups.flatMap { group in
                let keeper = duplicateKeeper(for: group)
                return group.files.filter {
                    !$0.isProtected && $0.url != keeper.url && selectedDuplicates.contains($0.url)
                }.map { file in
                    PlannedAction.trash(
                        TrashTarget(
                            url: file.url, root: file.root, stamp: file.stamp, category: .reviewedFile,
                            estimatedBytes: file.allocatedBytes, keeperURL: keeper.url,
                            keeperStamp: keeper.stamp))
                }
            }
        } else {
            let selected = result.largeFiles.filter { !$0.isProtected && selectedLargeFiles.contains($0.url) }
            let urls = Set(selected.map(\.url))
            for group in result.duplicateGroups where group.files.contains(where: { urls.contains($0.url) }) {
                if group.files.allSatisfy({ urls.contains($0.url) }) {
                    workflowNotice = .keepAtLeastOne
                    return
                }
            }
            actions = selected.map { file in
                let group = result.duplicateGroups.first { $0.files.contains(file) }
                let keeper = group?.files.first { !urls.contains($0.url) }
                return .trash(
                    TrashTarget(
                        url: file.url, root: file.root, stamp: file.stamp, category: .reviewedFile,
                        estimatedBytes: file.allocatedBytes, keeperURL: keeper?.url, keeperStamp: keeper?.stamp))
            }
        }
        guard !actions.isEmpty else { return }
        pendingReview = CleanupReview(actions: actions, source: .fileCleanup)
    }

    func approveCleanup(_ review: CleanupReview) {
        guard !isBusy, pendingReview?.id == review.id else { return }
        pendingReview = nil
        execute(review.actions, source: review.source, boost: false)
    }

    func duplicateKeeper(for group: DuplicateGroup) -> ScannedFile {
        group.files.first { $0.url == duplicateKeepers[group.id] } ?? group.keeper
    }

    func keepDuplicate(_ file: ScannedFile, in group: DuplicateGroup) {
        guard !isBusy, group.files.contains(file) else { return }
        duplicateKeepers[group.id] = file.url
        selectedDuplicates.remove(file.url)
    }

    func updateLargeThreshold(_ value: Int) {
        guard !isBusy else { return }
        minimumLargeFileMiB = max(1, value)
        defaults.set(minimumLargeFileMiB, forKey: "macpulse.largeThreshold")
        fileResult = nil
        selectedLargeFiles = []
        selectedDuplicates = []
    }

    func requestQuit(_ process: ProcessReading) {
        guard !isBusy else { return }
        selectedProcess = nil
        execute([.quit(process)], source: .gracefulQuit, boost: false)
    }

    func requestDeveloperStop(_ process: DeveloperProcessReading) {
        guard !isBusy else { return }
        execute([.stopDeveloper(process)], source: .developerStop, boost: false)
    }

    private func execute(_ actions: [PlannedAction], source: ActivityKind, boost: Bool) {
        guard !isBusy, !actions.isEmpty else { return }
        operation = .applying
        if boost { boostStage = .executing }
        operationTask = Task { [self] in
            let report = await executor.execute(actions) { [weak self] progress in
                self?.executionProgress = progress
            }
            let status: ActivityStatus =
                report.wasCancelled
                ? .cancelled
                : (report.succeededCount == report.items.count
                    ? .completed : (report.succeededCount == 0 ? .failed : .partial))
            _ = activityStore.recordOperation(
                kind: source, status: status, count: report.succeededCount,
                estimatedBytes: report.movedEstimatedBytes,
                availableStorageDelta: report.storageChange)
            activityRecords = activityStore.records
            let moved = Set(report.items.compactMap { $0.outcome == .moved ? $0.url : nil })
            let movedPaths = Set(moved.map { FilePathPolicy.normalized($0).path })
            cacheCandidates.removeAll { movedPaths.contains(FilePathPolicy.normalized($0.url).path) }
            selectedCaches = selectedCaches.filter { !movedPaths.contains(FilePathPolicy.normalized($0).path) }
            selectedLargeFiles.subtract(moved)
            selectedDuplicates.subtract(moved)
            // Remove stale scan results after any move; a new scan verifies surviving duplicate groups.
            if !moved.isEmpty { fileResult = nil }
            await refresh()
            operation = .idle
            operationTask = nil
            executionProgress = nil
            if boost {
                boostReport = report
                boostStage = .results
            } else {
                presentedReport = report
            }
        }
    }

    func startBoost() {
        guard !isBusy else { return }
        isBoostPresented = true
        boostStage = .scanning
        boostScanMessage = .verifyBefore
        boostReport = nil
        boostPlan = nil
        boostSelectedApps = []
        boostSelectedCaches = []
        workflowError = nil
        operation = .boostScan
        operationTask = Task {
            defer {
                operation = .idle
                operationTask = nil
            }
            do {
                let measurement = try await executor.measure()
                boostScanMessage = .scanEnumerating
                let caches = try await scanner.scan(root: cacheRoot)
                try Task.checkCancellation()
                let fresh = try await provider.snapshot()
                snapshot = fresh
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let apps = fresh.processes.filter {
                    !ProcessProtectionPolicy.isProtected($0, ownBundleIdentifier: Bundle.main.bundleIdentifier)
                        && $0.executablePath != nil && $0.launchDate != nil && $0.pid != frontmostPID
                }
                boostPlan = BoostPlan(
                    measurement: measurement,
                    findings: diagnosis.findings(for: fresh, sustainedCPU: highCPUSampleCount >= 3),
                    applications: apps, caches: caches)
                cacheCandidates = caches
                cacheScanCompleted = true
                recordCacheScan(caches)
                boostStage = .review
            } catch is CancellationError {
                boostStage = .failed
                workflowNotice = .operationCancelled
            } catch {
                boostStage = .failed
                workflowError = error.localizedDescription
            }
        }
    }

    var selectedBoostActions: [PlannedAction] {
        guard let boostPlan else { return [] }
        return boostPlan.applications.filter { boostSelectedApps.contains($0.pid) }.map { .quit($0) }
            + cacheActions(ids: boostSelectedCaches, candidates: boostPlan.caches)
    }

    func approveBoost() {
        let actions = selectedBoostActions
        guard !actions.isEmpty else { return }
        execute(actions, source: .smartBoost, boost: true)
    }

    func reveal(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            workflowNotice = .itemNoLongerExists
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openTrash() {
        do {
            let trash = try FileManager.default.url(
                for: .trashDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false)
            if !NSWorkspace.shared.open(trash) { workflowNotice = .finderUnavailable }
        } catch { workflowError = error.localizedDescription }
    }

    func waitForCurrentOperation() async { await operationTask?.value }
}

/// Avoid rebuilding the SwiftUI window once for every small file. Service callbacks stay
/// unthrottled for cancellation/testing; only UI publications are rate-limited.
private actor FileScanUIThrottle {
    private var lastStage: FileDiscoveryStage?
    private var lastUpdate: ContinuousClock.Instant?
    func shouldPublish(_ stage: FileDiscoveryStage) -> Bool {
        let now = ContinuousClock().now
        let expired = lastUpdate.map { $0.duration(to: now) >= .milliseconds(150) } ?? true
        if lastStage != stage || expired {
            lastStage = stage
            lastUpdate = now
            return true
        }
        return false
    }
}
