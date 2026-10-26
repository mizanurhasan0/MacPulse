import SwiftUI

struct CleanupReviewView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    let review: CleanupReview

    var body: some View {
        VStack(spacing: 0) {
            PageScrollView {
                Text(localization.workflow(.cleanupReview)).font(.largeTitle.bold())
                InfoNote(text: localization.workflow(.cleanupReviewIntro))
                if let notice = model.workflowNotice, notice == .itemNoLongerExists {
                    InfoNote(text: localization.workflow(notice))
                }
                if let error = model.workflowError { InfoNote(text: error, symbol: "exclamationmark.triangle") }
                InfoNote(text: localization.workflow(.trashWarning), symbol: "trash")
                Text(
                    "\(localization.workflow(.selectedCount, review.actions.count)) · \(formatBytes(review.estimatedBytes))"
                )
                .font(.headline)
                LazyVStack(spacing: 10) {
                    ForEach(review.actions) { action in
                        SurfaceCard(padding: 16) {
                            Text(action.title).font(.headline)
                            if case .trash(let target) = action {
                                Text(target.url.path).font(.caption).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button(localization.workflow(.revealFinder)) { model.reveal(target.url) }.buttonStyle(
                                    .borderless)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button(localization.text(.cancel)) { model.pendingReview = nil }.keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("cleanup.cancel")
                Spacer()
                Button(localization.workflow(.moveToTrash), role: .destructive) { model.approveCleanup(review) }
                    .buttonStyle(.borderedProminent).disabled(model.isBusy)
                    .accessibilityIdentifier("cleanup.confirm-trash")
            }.padding(20)
        }
        .frame(minWidth: 560, idealWidth: 760, minHeight: 480, idealHeight: 650)
    }
}

struct SmartBoostView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            PageScrollView {
                Text(localization.text(.smartBoost)).font(.largeTitle.bold())
                if model.workflowNotice == .itemNoLongerExists {
                    InfoNote(text: localization.workflow(.itemNoLongerExists))
                }
                switch model.boostStage {
                case .scanning:
                    SurfaceCard {
                        ProgressView(localization.workflow(model.boostScanMessage))
                        InfoNote(text: localization.text(.cacheScanDescription))
                        ScanCancellationRow()
                    }
                case .review:
                    if let plan = model.boostPlan { review(plan) }
                case .executing:
                    ExecutionProgressCard()
                case .results:
                    if let report = model.boostReport { ActionReportContent(report: report) }
                case .failed:
                    InfoNote(
                        text: model.workflowError ?? localization.workflow(model.workflowNotice ?? .operationFailed),
                        symbol: "exclamationmark.triangle")
                    Button(localization.workflow(.retry)) { model.startBoost() }.buttonStyle(.borderedProminent)
                }
            }
            Divider()
            HStack {
                Button(localization.workflow(.done)) { model.isBoostPresented = false }
                    .accessibilityIdentifier("boost.done")
                    .disabled(model.isBusy).keyboardShortcut(.cancelAction)
                Spacer()
                if model.boostStage == .review {
                    Text(localization.workflow(.selectedCount, model.selectedBoostActions.count)).font(.caption)
                        .foregroundStyle(.secondary)
                    Button(localization.workflow(.executePlan)) { confirming = true }
                        .buttonStyle(.borderedProminent).disabled(model.selectedBoostActions.isEmpty || model.isBusy)
                        .accessibilityIdentifier("boost.execute-selected")
                }
            }.padding(20)
        }
        .frame(minWidth: 600, idealWidth: 860, minHeight: 520, idealHeight: 700)
        .interactiveDismissDisabled(model.isBusy)
        .confirmationDialog(localization.workflow(.executePlan), isPresented: $confirming, titleVisibility: .visible) {
            Button(localization.workflow(.executePlan), role: .destructive) { model.approveBoost() }
                .accessibilityIdentifier("boost.confirm-selected")
            Button(localization.text(.cancel), role: .cancel) {}
        } message: {
            Text(localization.workflow(.reviewSafety) + "\n\n" + localization.workflow(.trashWarning))
        }
    }

    private func review(_ plan: BoostPlan) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(localization.workflow(.boostReview)).font(.title2.bold())
            InfoNote(text: localization.workflow(.boostIntro))
            InfoNote(text: localization.workflow(.reviewSafety), symbol: "hand.raised")
            if !plan.findings.isEmpty {
                Text(localization.workflow(.boostAdvice)).font(.headline)
                ForEach(plan.findings) { FindingCard(finding: $0, dismissOnNavigate: true) }
            }
            Text(localization.workflow(.boostApplications)).font(.title3.bold())
            if plan.applications.isEmpty { Text(localization.workflow(.noEligibleApps)).foregroundStyle(.secondary) }
            LazyVStack(spacing: 10) {
                ForEach(plan.applications) { app in
                    SurfaceCard(padding: 16) {
                        Toggle(
                            isOn: Binding(
                                get: { model.boostSelectedApps.contains(app.pid) },
                                set: {
                                    if $0 {
                                        model.boostSelectedApps.insert(app.pid)
                                    } else {
                                        model.boostSelectedApps.remove(app.pid)
                                    }
                                })
                        ) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(app.name).font(.headline)
                                Text("\(formatBytes(app.memoryBytes)) · PID \(app.pid)").font(
                                    .caption.monospacedDigit()
                                ).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox)
                    }
                }
            }
            Text(localization.workflow(.boostCaches)).font(.title3.bold())
            InfoNote(text: localization.workflow(.cacheRebuildWarning))
            if plan.caches.isEmpty { Text(localization.workflow(.noEligibleCaches)).foregroundStyle(.secondary) }
            LazyVStack(spacing: 10) {
                ForEach(plan.caches) { CacheSelectionRow(candidate: $0, selection: $model.boostSelectedCaches) }
            }
        }
    }
}

struct ExecutionProgressCard: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        SurfaceCard {
            if let progress = model.executionProgress {
                ProgressView(localization.workflow(phaseKey(progress.phase)))
                Text(localization.workflow(.progressCount, progress.completed, progress.total)).font(.callout)
            } else {
                ProgressView(localization.workflow(.verifyBefore))
            }
            InfoNote(text: localization.workflow(.cancelExplanation))
            Button(localization.workflow(.cancelWork)) { model.cancelOperation() }.buttonStyle(.bordered)
        }
    }

    private func phaseKey(_ phase: ExecutionPhase) -> WorkflowKey {
        switch phase {
        case .measuringBefore: .verifyBefore
        case .applying: .applyingActions
        case .measuringAfter: .verifyAfter
        }
    }
}

struct ActionReportView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    let report: ActionReport

    var body: some View {
        VStack(spacing: 0) {
            PageScrollView {
                if let error = model.workflowError { InfoNote(text: error, symbol: "exclamationmark.triangle") }
                ActionReportContent(report: report)
            }
            Divider()
            HStack {
                Button(localization.workflow(.openTrash)) { model.openTrash() }
                Spacer()
                Button(localization.workflow(.done)) { model.presentedReport = nil }
                    .accessibilityIdentifier("report.done")
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(minWidth: 600, idealWidth: 820, minHeight: 500, idealHeight: 680)
    }
}

struct ActionReportContent: View {
    @EnvironmentObject private var localization: LocalizationStore
    let report: ActionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(localization.workflow(.observedResults)).font(.largeTitle.bold())
            StatusPill(
                text: localization.workflow(
                    report.wasCancelled
                        ? .cancelledStatus
                        : (report.succeededCount == report.items.count
                            ? .done : (report.succeededCount == 0 ? .failedStatus : .partialStatus))),
                color: report.succeededCount == report.items.count && !report.wasCancelled ? .green : .orange)
            InfoNote(text: localization.workflow(.resultsWarning))
            if let path = report.before?.storageRoot?.path {
                Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if report.movedEstimatedBytes > 0 {
                Text("\(localization.workflow(.estimatedMoved)): \(formatBytes(report.movedEstimatedBytes))").font(
                    .headline)
            }
            if let before = report.before, let after = report.after {
                InfoNote(
                    text: localization.workflow(
                        .measurementWindows, before.windowSeconds, before.cpuSampleCount,
                        after.windowSeconds, after.cpuSampleCount))
                MeasurementComparison(
                    title: localization.workflow(.cpuWindow),
                    before: cpu(before.averageCPU), after: cpu(after.averageCPU))
                MeasurementComparison(
                    title: localization.workflow(.availableMemory),
                    before: availableMemory(before.snapshot.memory), after: availableMemory(after.snapshot.memory))
                MeasurementComparison(
                    title: localization.workflow(.availableDisk),
                    before: availableStorage(before.snapshot.storage),
                    after: availableStorage(after.snapshot.storage),
                    change: report.storageChange.map(signedBytes))
                MeasurementComparison(
                    title: localization.text(.swap),
                    before: before.snapshot.memory.swapUsedBytes.map(formatBytes) ?? localization.text(.unavailable),
                    after: after.snapshot.memory.swapUsedBytes.map(formatBytes) ?? localization.text(.unavailable))
                MeasurementComparison(
                    title: localization.workflow(.applicationCount),
                    before: String(before.snapshot.processes.count), after: String(after.snapshot.processes.count))
            } else {
                InfoNote(text: localization.workflow(.noMeasurement))
            }
            LazyVStack(spacing: 10) {
                ForEach(report.items) { item in
                    SurfaceCard(padding: 16) {
                        Text(item.title).font(.headline)
                        Label(
                            localization.workflow(outcomeKey(item.outcome)),
                            systemImage: success(item.outcome) ? "checkmark.circle.fill" : "exclamationmark.circle"
                        )
                        .font(.callout).foregroundStyle(success(item.outcome) ? .green : .secondary)
                        if let detail = item.detail, !detail.isEmpty {
                            DisclosureGroup(localization.workflow(.details)) {
                                Text(detail).font(.caption).textSelection(.enabled).fixedSize(
                                    horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cpu(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(1)).locale(localization.language.locale)) + "%" }
            ?? localization.text(.unavailable)
    }
    private func availableMemory(_ memory: MemoryReading) -> String {
        guard let fraction = memory.estimatedAvailableFraction else { return localization.text(.unavailable) }
        return formatBytes(UInt64(Double(memory.physicalBytes) * fraction))
    }
    private func success(_ outcome: ActionOutcome) -> Bool { outcome == .moved || outcome == .quit }
    private func availableStorage(_ storage: StorageReading) -> String {
        storage.totalBytes > 0 ? formatBytes(storage.availableBytes) : localization.text(.unavailable)
    }
    private func outcomeKey(_ outcome: ActionOutcome) -> WorkflowKey {
        switch outcome {
        case .moved: .successMoved
        case .quit: .successQuit
        case .stillRunning: .stillWaiting
        case .requested: .stopRequested
        case .rejected: .requestRejected
        case .changed: .identityChanged
        case .cancelled: .actionCancelled
        case .failed: .actionFailed
        }
    }
}

private struct MeasurementComparison: View {
    @EnvironmentObject private var localization: LocalizationStore
    let title: String
    let before: String
    let after: String
    var change: String? = nil
    var body: some View {
        SurfaceCard(padding: 16) {
            Text(title).font(.headline)
            HStack(alignment: .top, spacing: 20) {
                value(.before, before)
                value(.after, after)
                if let change { value(.observedChange, change) }
            }
        }
    }
    private func value(_ key: WorkflowKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localization.workflow(key)).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.callout.weight(.semibold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func signedBytes(_ value: Int64) -> String {
    (value > 0 ? "+" : (value < 0 ? "−" : "")) + formatBytes(UInt64(value.magnitude))
}
