import AppKit
import Combine
import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        PageScrollView {
            pageHeader(.recommendations, subtitle: .recommendationsIntro)
            if model.findings.isEmpty {
                SurfaceCard {
                    ContentUnavailableView(
                        localization.text(.noRecommendations), systemImage: "checkmark.circle.fill",
                        description: Text(localization.text(.noFindings))
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            } else {
                ForEach(model.findings) { FindingCard(finding: $0) }
            }
        }
        .navigationTitle(localization.text(.recommendations))
    }
}

struct ProcessView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var query = ""

    private var visibleProcesses: [ProcessReading] {
        let processes = model.snapshot?.processes ?? []
        guard !query.isEmpty else { return processes }
        return processes.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
                || String($0.pid).contains(query)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    pageHeader(.processes, subtitle: .processDetails)
                    searchField
                    if model.operation == .applying { ExecutionProgressCard() }
                    if let key = processMessageKey {
                        InfoNote(text: localization.text(key))
                    }
                }
                .padding(WorkspaceMetrics.inset(for: geometry.size.width))

                if model.snapshot == nil {
                    ProgressView(localization.text(.readingMetrics))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleProcesses.isEmpty {
                    ContentUnavailableView(
                        localization.text(query.isEmpty ? .emptyProcesses : .noSearchResults),
                        systemImage: "rectangle.stack",
                        description: Text(
                            localization.text(query.isEmpty ? .emptyProcessesDetail : .noSearchResultsDetail))
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if geometry.size.width >= 720 {
                    processTable
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(visibleProcesses) { process in
                                CompactProcessRow(process: process) { model.selectedProcess = process }
                            }
                        }
                        .padding(.horizontal, WorkspaceMetrics.inset(for: geometry.size.width))
                        .padding(.bottom, 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()
                InfoNote(text: localization.workflow(.cpuPerCore))
                    .padding(.horizontal, WorkspaceMetrics.inset(for: geometry.size.width))
                    .padding(.vertical, 12)
            }
            .environment(\.workspaceWidth, geometry.size.width)
            .background(WorkspaceBackground())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(localization.text(.processes))
        .confirmationDialog(
            String(
                format: localization.text(.quitConfirmation),
                model.selectedProcess?.name ?? localization.text(.application)),
            isPresented: Binding(
                get: { model.selectedProcess != nil }, set: { if !$0 { model.selectedProcess = nil } }),
            titleVisibility: .visible
        ) {
            Button(localization.text(.quit), role: .destructive) { quitSelected() }
            Button(localization.text(.cancel), role: .cancel) { model.selectedProcess = nil }
        } message: {
            Text(localization.text(.quitWarning))
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(localization.text(.searchApplications), text: $query)
                .textFieldStyle(.plain)
                .accessibilityLabel(localization.text(.searchApplications))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(localization.text(.clearSearch))
            }
        }
        .padding(11)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))
    }

    private var processTable: some View {
        Table(visibleProcesses) {
            TableColumn(localization.text(.application)) { process in
                VStack(alignment: .leading, spacing: 3) {
                    Text(process.name).font(.body.weight(.medium)).lineLimit(1)
                    if let identifier = process.bundleIdentifier {
                        Text(identifier).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.vertical, 5)
            }
            .width(min: 160, ideal: 280)
            TableColumn(localization.text(.pid), value: \.pidText).width(65)
            TableColumn(localization.text(.cpu), value: \.cpuText).width(85)
            TableColumn(localization.text(.memoryFootprint), value: \.memoryFootprintText)
                .width(min: 100, ideal: 140, max: 160)
            TableColumn(localization.text(.action)) { process in
                QuitProcessButton(process: process) { model.selectedProcess = process }
                    .environmentObject(localization)
                    .environmentObject(model)
            }
            .width(min: 80, ideal: 100, max: 120)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var processMessageKey: TranslationKey? {
        guard let message = model.processActionMessage else { return nil }
        if message == localization.text(.identityChangedEnglish) { return .identityChanged }
        if message == localization.text(.quitRequestedEnglish) { return .quitRequested }
        if message == localization.text(.quitObservedEnglish) { return .quitObserved }
        if message == localization.text(.quitStillRunningEnglish) { return .quitStillRunning }
        return .quitFailed
    }

    private func quitSelected() {
        guard let target = model.selectedProcess else { return }
        model.requestQuit(target)
    }
}

private struct QuitProcessButton: View {
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var model: DashboardModel
    let process: ProcessReading
    let action: () -> Void

    private var isProtected: Bool {
        ProcessProtectionPolicy.isProtected(process, ownBundleIdentifier: Bundle.main.bundleIdentifier)
            || process.launchDate == nil
    }

    var body: some View {
        Button(localization.text(.quit), action: action)
            .buttonStyle(.bordered)
            .disabled(isProtected || model.isBusy)
            .help(localization.text(isProtected ? .protectedProcess : .quitWarning))
    }
}

private struct CompactProcessRow: View {
    @EnvironmentObject private var localization: LocalizationStore
    let process: ProcessReading
    let onQuit: () -> Void

    var body: some View {
        SurfaceCard(padding: 16) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    IconTile(symbol: "app", size: 36)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(process.name).font(.headline).lineLimit(2)
                        Text(process.bundleIdentifier ?? "\(localization.text(.pid)) \(process.pidText)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localization.text(.memoryFootprint)).font(.caption).foregroundStyle(.secondary)
                        Text(process.memoryFootprintText).font(.callout.weight(.semibold)).monospacedDigit()
                        Text("CPU \(process.cpuText)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    QuitProcessButton(process: process, action: onQuit)
                }
            }
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var isConfirmingClear = false

    var body: some View {
        PageScrollView {
            AdaptiveStack(alignment: .top) {
                pageHeader(.history, subtitle: model.activityRecords.isEmpty ? .noHistoryDetail : .historySummary)
                if !model.activityRecords.isEmpty {
                    Button(localization.text(.clearHistory), role: .destructive) { isConfirmingClear = true }
                        .buttonStyle(.bordered).fixedSize(horizontal: true, vertical: false)
                }
            }
            if model.activityRecords.isEmpty {
                ContentUnavailableView(
                    localization.text(.noHistory), systemImage: "clock.arrow.circlepath",
                    description: Text(localization.text(.noHistoryDetail))
                )
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.activityRecords) { ActivityRecordCard(record: $0) }
                }
            }
            InfoNote(text: localization.text(.historyPrivacy), symbol: "lock.shield")
        }
        .navigationTitle(localization.text(.history))
        .confirmationDialog(
            localization.text(.clearHistoryConfirmation), isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(localization.text(.clearHistory), role: .destructive) { model.clearActivityHistory() }
            Button(localization.text(.cancel), role: .cancel) {}
        } message: {
            Text(localization.text(.clearHistoryMessage))
        }
    }
}

private struct ActivityRecordCard: View {
    @EnvironmentObject private var localization: LocalizationStore
    let record: ActivityRecord

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 14) {
                IconTile(symbol: record.kind == .cacheScan ? "externaldrive" : "power", size: 36)
                VStack(alignment: .leading, spacing: 8) {
                    Text(summary).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(record.date, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary)
                    if record.kind != .gracefulQuit {
                        Text(localization.workflow(.historyItemCount, record.count))
                            .font(.callout).foregroundStyle(.secondary)
                        if let bytes = record.estimatedBytes, bytes > 0 {
                            Text(
                                "\(localization.text(.estimatedData)): \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
                            )
                            .font(.callout).foregroundStyle(.secondary)
                        }
                        if let change = record.availableStorageDelta {
                            Text("\(localization.workflow(.availableDisk)): \(signedBytes(change))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if record.status == .partial || record.status == .cancelled || record.status == .failed {
                        Text(
                            localization.workflow(
                                record.status == .cancelled
                                    ? .cancelledStatus : (record.status == .failed ? .failedStatus : .partialStatus))
                        )
                        .font(.caption).foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        switch (record.kind, record.status) {
        case (.cacheScan, .completed): localization.text(.cacheScanCompleted)
        case (.cacheScan, .partial): localization.text(.cacheScanPartial)
        case (.gracefulQuit, .requested): localization.text(.gracefulQuitRequested)
        case (.gracefulQuit, .notAccepted): localization.text(.gracefulQuitNotAccepted)
        case (.gracefulQuit, _): localization.workflow(.quitHistory)
        case (.cacheCleanup, _): localization.workflow(.cacheCleanupHistory)
        case (.fileScan, _): localization.workflow(.fileScanHistory)
        case (.fileCleanup, _): localization.workflow(.fileCleanupHistory)
        case (.smartBoost, _): localization.workflow(.boostHistory)
        case (.developerStop, _): localization.workflow(.developerStopHistory)
        default: localization.text(.activityRecorded)
        }
    }
}

struct LoginItemsView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @State private var isPresentingOpenError = false

    var body: some View {
        PageScrollView {
            pageHeader(.startupLoginItems, subtitle: .startupLoginItemsIntro)
            SurfaceCard {
                AdaptiveStack {
                    HStack(alignment: .top, spacing: 14) {
                        IconTile(symbol: "person.crop.circle.badge.plus")
                        VStack(alignment: .leading, spacing: 8) {
                            LText(key: .loginItemsWhere, font: .headline)
                            LText(key: .loginItemsWhereDetail, color: .secondary)
                                .font(.callout).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: openLoginItemsSettings) {
                        Label(localization.text(.openSystemSettings), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(localization.text(.loginItemsSettingsButton))
                    .accessibilityIdentifier("login-items.open-system-settings")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                LoginItemsInfoCard(
                    title: .openAtLogin, detail: .openAtLoginDetail, symbol: "rectangle.stack.badge.plus")
                LoginItemsInfoCard(title: .backgroundItems, detail: .backgroundItemsDetail, symbol: "gearshape.2")
            }
            InfoNote(text: localization.text(.loginItemsLimitsDetail))
            InfoNote(text: localization.text(.loginItemsNoChanges), symbol: "lock.shield")
        }
        .navigationTitle(localization.text(.startupLoginItems))
        .alert(localization.text(.systemSettingsOpenFailed), isPresented: $isPresentingOpenError) {
            Button(localization.text(.cancel), role: .cancel) {}
        }
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
            NSWorkspace.shared.open(url)
        else {
            isPresentingOpenError = true
            return
        }
    }
}

private struct LoginItemsInfoCard: View {
    @EnvironmentObject private var localization: LocalizationStore
    let title: TranslationKey
    let detail: TranslationKey
    let symbol: String

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                IconTile(symbol: symbol)
                LText(key: title, font: .headline)
                LText(key: detail, color: .secondary).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        }
    }
}
