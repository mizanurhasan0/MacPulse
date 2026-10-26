import AppKit
import Foundation

enum PlannedAction: Identifiable, Sendable {
    case quit(ProcessReading)
    case trash(TrashTarget)
    case stopDeveloper(DeveloperProcessReading)

    var id: String {
        switch self {
        case .quit(let process): "quit:\(process.pid)"
        case .trash(let target): "trash:\(target.url.path)"
        case .stopDeveloper(let process): "developer-stop:\(process.pid)"
        }
    }
    var title: String {
        switch self {
        case .quit(let process): process.name
        case .trash(let target): target.url.lastPathComponent
        case .stopDeveloper(let process): "\(process.name) (\(process.pid))"
        }
    }
    var estimatedBytes: UInt64 {
        switch self {
        case .quit, .stopDeveloper: 0
        case .trash(let target): target.estimatedBytes
        }
    }
}

enum ActionOutcome: String, Sendable {
    case moved, quit, stillRunning, requested, rejected, changed, cancelled, failed
}

struct ActionItemResult: Identifiable, Sendable {
    var id = UUID()
    var title: String
    var outcome: ActionOutcome
    var detail: String?
    var estimatedBytes: UInt64 = 0
    var url: URL? = nil
}

struct PerformanceMeasurement: Sendable {
    var snapshot: PerformanceSnapshot
    var averageCPU: Double?
    var cpuSampleCount: Int
    var windowSeconds: Double
    var storageRoot: URL? = nil
}

struct ActionReport: Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var before: PerformanceMeasurement?
    var after: PerformanceMeasurement?
    var items: [ActionItemResult]
    var wasCancelled: Bool
    var movedEstimatedBytes: UInt64 {
        items.filter { $0.outcome == .moved }.reduce(0) { $0 + $1.estimatedBytes }
    }
    var succeededCount: Int { items.filter { $0.outcome == .moved || $0.outcome == .quit }.count }
    var storageChange: Int64? {
        guard let before, let after, before.snapshot.storage.totalBytes > 0, after.snapshot.storage.totalBytes > 0
        else { return nil }
        return Int64(clamping: after.snapshot.storage.availableBytes)
            - Int64(clamping: before.snapshot.storage.availableBytes)
    }
}

enum ExecutionPhase: Sendable { case measuringBefore, applying, measuringAfter }
struct ExecutionProgress: Sendable {
    var phase: ExecutionPhase
    var completed: Int
    var total: Int
}

@MainActor protocol ApplicationQuitting {
    func quit(_ target: ProcessReading) async -> ActionItemResult
}

@MainActor struct GracefulApplicationQuitter: ApplicationQuitting {
    func quit(_ target: ProcessReading) async -> ActionItemResult {
        guard !Task.isCancelled else { return ActionItemResult(title: target.name, outcome: .cancelled) }
        guard !ProcessProtectionPolicy.isProtected(target, ownBundleIdentifier: Bundle.main.bundleIdentifier),
            let bundle = target.bundleIdentifier, let path = target.executablePath,
            let launched = target.launchDate,
            let app = NSRunningApplication(processIdentifier: target.pid),
            app.launchDate == launched,
            app.bundleIdentifier == bundle,
            app.executableURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
        else {
            return ActionItemResult(title: target.name, outcome: .changed)
        }
        guard app.terminate() else { return ActionItemResult(title: target.name, outcome: .rejected) }
        for _ in 0..<15 {
            // A sent quit request cannot be withdrawn. Cancellation stops the rest of the plan.
            if Task.isCancelled { return ActionItemResult(title: target.name, outcome: .requested) }
            try? await Task.sleep(for: .milliseconds(200))
            guard let current = NSRunningApplication(processIdentifier: target.pid) else {
                return ActionItemResult(title: target.name, outcome: .quit)
            }
            guard current.bundleIdentifier == bundle,
                current.launchDate == launched,
                current.executableURL?.standardizedFileURL.path == path
            else {
                return ActionItemResult(title: target.name, outcome: .changed)
            }
            if current.isTerminated { return ActionItemResult(title: target.name, outcome: .quit) }
        }
        return ActionItemResult(title: target.name, outcome: .stillRunning)
    }
}

/// All user-approved quit and Trash actions go through this executor.
@MainActor final class ActionExecutor {
    private let provider: any SystemMetricsProvider
    private let quitter: any ApplicationQuitting
    private let trashService: TrashService
    private let sampleInterval: Duration
    private let developerProcesses = DeveloperProcessService()

    init(
        provider: any SystemMetricsProvider = LiveSystemMetricsProvider(),
        quitter: any ApplicationQuitting = GracefulApplicationQuitter(),
        trashService: TrashService = TrashService(), sampleInterval: Duration = .milliseconds(500)
    ) {
        self.provider = provider
        self.quitter = quitter
        self.trashService = trashService
        self.sampleInterval = sampleInterval
    }

    func measure(storageRoot: URL? = nil) async throws -> PerformanceMeasurement {
        let clock = ContinuousClock()
        let start = clock.now
        var samples: [Double] = []
        var latest = try await provider.snapshot()
        // Discard the first interval; each report compares two equally spaced interval samples.
        for _ in 0..<2 {
            try await Task.sleep(for: sampleInterval)
            try Task.checkCancellation()
            latest = try await provider.snapshot()
            if latest.cpu.isAvailable { samples.append(latest.cpu.total) }
        }
        let elapsed = start.duration(to: clock.now).components
        if let storageRoot {
            if let values = try? storageRoot.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
            ]) {
                let total = UInt64(max(0, values.volumeTotalCapacity ?? 0))
                let available =
                    values.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) }
                    ?? UInt64(max(0, values.volumeAvailableCapacity ?? 0))
                latest.storage = StorageReading(totalBytes: total, availableBytes: min(total, available))
            } else {
                latest.storage = StorageReading(totalBytes: 0, availableBytes: 0)
            }
        }
        return PerformanceMeasurement(
            snapshot: latest,
            averageCPU: samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count),
            cpuSampleCount: samples.count,
            windowSeconds: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
            storageRoot: storageRoot)
    }

    func execute(
        _ requestedActions: [PlannedAction],
        progress: @escaping @MainActor (ExecutionProgress) -> Void
    ) async -> ActionReport {
        var seen = Set<String>()
        let actions = requestedActions.filter { seen.insert($0.id).inserted }
        let storageRoot = actions.compactMap { action -> URL? in
            if case .trash(let target) = action { return target.root }
            return nil
        }.first
        var results: [ActionItemResult] = []
        progress(ExecutionProgress(phase: .measuringBefore, completed: 0, total: actions.count))
        let before: PerformanceMeasurement?
        do { before = try await measure(storageRoot: storageRoot) } catch {
            return ActionReport(
                before: nil, after: nil,
                items: actions.map {
                    ActionItemResult(
                        title: $0.title, outcome: Task.isCancelled ? .cancelled : .failed,
                        detail: error.localizedDescription)
                },
                wasCancelled: Task.isCancelled)
        }

        // Preserve duplicates globally, including targets selected through different UI sections.
        let selectedURLs = Set(
            actions.compactMap { action -> URL? in
                if case .trash(let target) = action { return target.url.standardizedFileURL }
                return nil
            })
        for (index, action) in actions.enumerated() {
            progress(ExecutionProgress(phase: .applying, completed: index, total: actions.count))
            if Task.isCancelled {
                results += actions[index...].map { ActionItemResult(title: $0.title, outcome: .cancelled) }
                break
            }
            switch action {
            case .quit(let process):
                results.append(await quitter.quit(process))
            case .stopDeveloper(let process):
                let stopped = await developerProcesses.stop(target: process)
                let outcome: ActionOutcome =
                    switch stopped {
                    case .terminated, .alreadyExited: .quit
                    case .identityChanged, .protected: .changed
                    case .permissionDenied: .rejected
                    case .stillRunning: .stillRunning
                    case .requested: .requested
                    case .cancelled: .cancelled
                    case .failed: .failed
                    }
                results.append(ActionItemResult(title: action.title, outcome: outcome))
            case .trash(let target):
                if let keeper = target.keeperURL, selectedURLs.contains(keeper.standardizedFileURL) {
                    results.append(
                        ActionItemResult(
                            title: action.title, outcome: .failed,
                            detail: "At least one verified duplicate must be kept."))
                    continue
                }
                let active = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                let batch = await trashService.move(targets: [target], runningBundleIDs: active)
                for item in batch.items {
                    let outcome: ActionOutcome =
                        switch item.status {
                        case .moved: .moved
                        case .failed: .failed
                        case .cancelled: .cancelled
                        }
                    results.append(
                        ActionItemResult(
                            title: action.title, outcome: outcome,
                            detail: outcome == .moved ? nil : item.message,
                            estimatedBytes: item.estimatedBytes, url: item.url))
                }
            }
        }
        let cancelled = Task.isCancelled
        progress(ExecutionProgress(phase: .measuringAfter, completed: actions.count, total: actions.count))
        // Complete the short observation even when the user has cancelled future actions.
        let after = await Task { @MainActor [self] in try? await measure(storageRoot: storageRoot) }.value
        return ActionReport(before: before, after: after, items: results, wasCancelled: cancelled)
    }
}
