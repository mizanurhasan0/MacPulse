import SwiftUI

private enum MacPulseSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case recommendations = "Recommendations"
    case processes = "Processes"
    case storage = "Storage"
    case developerTools = "Developer Tools"
    case loginItems = "Startup & Login Items"
    case history = "Activity History"
    case settings = "Settings"

    var id: String { rawValue }
    var key: TranslationKey {
        switch self {
        case .dashboard: .dashboard
        case .recommendations: .recommendations
        case .processes: .processes
        case .storage: .storage
        case .developerTools: .developerTools
        case .loginItems: .startupLoginItems
        case .history: .history
        case .settings: .settings
        }
    }
    var symbol: String {
        switch self {
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .recommendations: "lightbulb"
        case .processes: "cpu"
        case .storage: "internaldrive"
        case .developerTools: "hammer"
        case .loginItems: "person.crop.circle.badge.plus"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section(localization.text(.sidebarMonitor)) {
                    navigationRows([.dashboard, .recommendations, .processes])
                }
                Section(localization.text(.sidebarWorkspace)) {
                    navigationRows([.storage, .developerTools, .loginItems])
                }
                Section {
                    navigationRows([.history, .settings])
                }
            }
            .navigationTitle("MacPulse")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(.tint)
                    LText(key: .localOnly, color: .secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        } detail: {
            Group {
                switch model.selectedSection {
                case MacPulseSection.storage.rawValue: StorageView()
                case MacPulseSection.processes.rawValue: ProcessView()
                case MacPulseSection.recommendations.rawValue: RecommendationsView()
                case MacPulseSection.developerTools.rawValue: DeveloperView()
                case MacPulseSection.loginItems.rawValue: LoginItemsView()
                case MacPulseSection.settings.rawValue: SettingsView()
                case MacPulseSection.history.rawValue: HistoryView()
                default: DashboardView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label(localization.text(.refresh), systemImage: "arrow.clockwise")
                    }
                    .help(localization.text(.refresh))
                    .keyboardShortcut("r", modifiers: .command)
                    .accessibilityIdentifier("toolbar.refresh")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .id(localization.language.rawValue)
        .task { model.startMonitoring() }
        .onDisappear {
            model.stopMonitoring()
            model.cancelOperation()
        }
        .environment(\.locale, Locale(identifier: localization.language.rawValue))
        .sheet(isPresented: $model.isBoostPresented) { SmartBoostView() }
        .sheet(item: $model.pendingReview) { CleanupReviewView(review: $0) }
        .sheet(item: $model.presentedReport) { ActionReportView(report: $0) }
        .alert(
            localization.workflow(.operationFailed),
            isPresented: Binding(
                get: { model.workflowError != nil && !model.isBoostPresented },
                set: { if !$0 { model.workflowError = nil } }
            )
        ) {
            Button(localization.workflow(.done)) { model.workflowError = nil }
        } message: {
            Text(model.workflowError ?? "")
        }
    }

    private func navigationRows(_ sections: [MacPulseSection]) -> some View {
        ForEach(sections) { section in
            Label(localization.text(section.key), systemImage: section.symbol)
                .padding(.vertical, 4)
                .tag(section.rawValue)
                .accessibilityIdentifier("nav.\(section.rawValue)")
        }
    }

    private var selection: Binding<String?> {
        Binding(
            get: { model.selectedSection },
            set: { value in
                if let value { model.selectedSection = value }
            })
    }
}

struct DashboardView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore

    private var snapshot: PerformanceSnapshot? { model.snapshot }

    var body: some View {
        PageScrollView {
            header
            if let error = model.lastError {
                ContentUnavailableView(
                    localization.text(.metricsUnavailable), systemImage: "exclamationmark.triangle",
                    description: Text(error))
            }
            if let snapshot {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 225), spacing: 16)], spacing: 16) {
                    MetricCard(
                        title: localization.text(.cpu), value: cpuValue(snapshot.cpu),
                        detail: cpuDetail(snapshot.cpu), symbol: "cpu",
                        state: snapshot.cpu.isAvailable
                            ? (snapshot.cpu.total >= 85 ? .attention : .healthy) : .unavailable,
                        progress: snapshot.cpu.isAvailable ? snapshot.cpu.total / 100 : nil)
                    MetricCard(
                        title: localization.text(.memoryState), value: healthLabel(snapshot.memory.pressure),
                        detail: memoryDetail(snapshot.memory), symbol: "memorychip", state: snapshot.memory.pressure)
                    MetricCard(
                        title: localization.text(.storageCapacity), value: storageValue(snapshot.storage),
                        detail: storageDetail(snapshot.storage), symbol: "internaldrive",
                        state: storageState(snapshot.storage),
                        progress: snapshot.storage.totalBytes > 0 ? snapshot.storage.usedFraction : nil)
                }
                RecentMetricsView()
                thermalOverview(snapshot.thermal)
                smartBoostCard
                recommendations
                InfoNote(text: localization.text(.measurementLimitations))
            } else if model.lastError == nil {
                ProgressView(localization.text(.readingMetrics))
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .navigationTitle(localization.text(.dashboard))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: .performanceOverview, subtitle: .dashboardIntro)
            HStack(spacing: 10) {
                StatusPill(
                    text: localization.text(model.monitoringEnabled ? .monitoringLive : .monitoringPaused),
                    color: model.monitoringEnabled ? .green : .secondary)
                if let date = snapshot?.timestamp {
                    Text(date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var smartBoostCard: some View {
        SurfaceCard(padding: 24) {
            AdaptiveStack {
                HStack(alignment: .top, spacing: 16) {
                    IconTile(symbol: "sparkles", size: 48)
                    VStack(alignment: .leading, spacing: 8) {
                        LText(key: .smartBoost, font: .title2.bold())
                        LText(key: .boostDescription, color: .secondary)
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.startBoost()
                } label: {
                    Label(localization.text(.scanAndReview), systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy)
                .controlSize(.large)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityIdentifier("dashboard.review-findings")
            }
        }
    }

    private func thermalOverview(_ thermal: ThermalReading) -> some View {
        SurfaceCard {
            AdaptiveStack(breakpoint: 620, alignment: .top) {
                HStack(alignment: .top, spacing: 14) {
                    IconTile(symbol: "thermometer.medium")
                    VStack(alignment: .leading, spacing: 8) {
                        LText(key: .thermalState, font: .headline)
                        Text(thermalLabel(thermal.state)).font(.title3.weight(.semibold))
                        Text(thermalDetail(thermal)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    LText(key: .temperatureCelsius, font: .headline)
                    Text(
                        thermal.temperatureCelsius.map {
                            $0.formatted(.number.precision(.fractionLength(1)).locale(localization.language.locale))
                                + " °C"
                        } ?? localization.text(.temperatureUnavailable)
                    )
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    if thermal.temperatureCelsius == nil {
                        LText(key: .thermalTempUnavailable, color: .secondary)
                            .font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var recommendations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LText(key: .recommendations, font: .title2.bold())
                Spacer()
                if !model.findings.isEmpty {
                    Text("\(model.findings.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("\(model.findings.count) \(localization.text(.recommendations))")
                }
            }
            if model.findings.isEmpty {
                Label(localization.text(.noFindings), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
            ForEach(model.findings) { finding in FindingCard(finding: finding) }
        }
    }

    private func cpuValue(_ cpu: CPUReading) -> String {
        cpu.isAvailable ? "\(Int(cpu.total.rounded()))%" : localization.text(.sampling)
    }
    private func cpuDetail(_ cpu: CPUReading) -> String {
        guard cpu.isAvailable else { return localization.text(.needsIntervalSample) }
        return
            "\(localization.text(.user)): \(Int(cpu.user.rounded()))%  ·  \(localization.text(.system)): \(Int(cpu.system.rounded()))%"
    }
    private func memoryDetail(_ memory: MemoryReading) -> String {
        let physical = ByteCountFormatter.string(fromByteCount: Int64(memory.physicalBytes), countStyle: .memory)
        let app = ByteCountFormatter.string(fromByteCount: Int64(memory.appBytes), countStyle: .memory)
        let swap =
            memory.swapUsedBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .memory) }
            ?? localization.text(.unavailable)
        return
            "\(physical) \(localization.text(.physical))  ·  \(app) \(localization.text(.appEstimate))  ·  \(localization.text(.swap)): \(swap)"
    }
    private func storageValue(_ storage: StorageReading) -> String {
        storage.totalBytes > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(storage.availableBytes), countStyle: .file)
            : localization.text(.unavailable)
    }
    private func storageDetail(_ storage: StorageReading) -> String {
        guard storage.totalBytes > 0 else { return localization.text(.storageUnavailable) }
        return
            "\(localization.text(.available)): \(ByteCountFormatter.string(fromByteCount: Int64(storage.availableBytes), countStyle: .file))  ·  \(Int((storage.usedFraction * 100).rounded()))% \(localization.text(.used))"
    }
    private func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: localization.text(.nominal)
        case .fair: localization.text(.fair)
        case .serious: localization.text(.serious)
        case .critical: localization.text(.critical)
        @unknown default: localization.text(.unavailable)
        }
    }
    private func thermalDetail(_ thermal: ThermalReading) -> String {
        "\(localization.text(.macOSThermalState)): \(thermalLabel(thermal.state))"
    }
    private func healthLabel(_ state: HealthState) -> String {
        switch state {
        case .healthy: localization.text(.healthy)
        case .attention: localization.text(.attention)
        case .critical: localization.text(.critical)
        case .unavailable: localization.text(.unavailable)
        }
    }
    private func storageState(_ storage: StorageReading) -> HealthState {
        guard storage.totalBytes > 0 else { return .unavailable }
        let availableFraction = Double(storage.availableBytes) / Double(storage.totalBytes)
        return availableFraction < 0.05 ? .critical : (availableFraction < 0.1 ? .attention : .healthy)
    }
}

struct MetricCard: View {
    @EnvironmentObject private var localization: LocalizationStore
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let state: HealthState
    var progress: Double? = nil

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: symbol).foregroundStyle(.tint).accessibilityHidden(true)
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Circle().fill(color).frame(width: 8, height: 8)
                        .accessibilityLabel(localization.text(stateKey))
                }
                Text(value)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .accessibilityAddTraits(.updatesFrequently)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let progress {
                    ProgressView(value: min(1, max(0, progress)))
                        .tint(state == .healthy ? nil : color)
                        .accessibilityLabel(title)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .healthy: .green
        case .attention: .orange
        case .critical: .red
        case .unavailable: .gray
        }
    }

    private var stateKey: TranslationKey {
        switch state {
        case .healthy: .healthy
        case .attention: .attention
        case .critical: .critical
        case .unavailable: .unavailable
        }
    }
}

struct FindingCard: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    let finding: Finding
    var dismissOnNavigate = false

    var body: some View {
        SurfaceCard {
            AdaptiveStack(breakpoint: 760, alignment: .top) {
                HStack(alignment: .top, spacing: 14) {
                    Image(
                        systemName: finding.severity == .critical
                            ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(finding.severity == .critical ? .red : .orange)
                    .font(.title3).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(localizedTitle).font(.headline)
                        Text(localizedDetail).font(.callout).foregroundStyle(.secondary)
                        Text(localizedEvidence).font(.caption).foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    model.selectedSection = finding.destination
                    if dismissOnNavigate { model.isBoostPresented = false }
                } label: {
                    Label(localization.text(.openSection), systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                Button(localization.workflow(.snoozeHour)) { model.snoozeFinding(finding.id) }
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var localizedTitle: String {
        switch finding.id {
        case "storage-low": localization.text(.lowStorageTitle)
        case "memory-pressure": localization.text(.highMemoryTitle)
        case "cpu-busy": localization.text(.highCPUTitle)
        case "thermal-elevated": localization.text(.elevatedThermalTitle)
        default: finding.title
        }
    }
    private var localizedDetail: String {
        switch finding.id {
        case "storage-low": localization.text(.lowStorageDetail)
        case "memory-pressure": localization.text(.highMemoryDetail)
        case "cpu-busy": localization.text(.highCPUDetail)
        case "thermal-elevated": localization.text(.elevatedThermalDetail)
        default: finding.detail
        }
    }

    private var localizedEvidence: String {
        guard let snapshot = model.snapshot else { return finding.evidence }
        switch finding.id {
        case "storage-low":
            let available = ByteCountFormatter.string(
                fromByteCount: Int64(snapshot.storage.availableBytes), countStyle: .file)
            let percent = Int(
                (Double(snapshot.storage.availableBytes) / Double(max(snapshot.storage.totalBytes, 1)) * 100).rounded())
            return String(
                format: localization.text(.evidenceStorage), locale: localization.language.locale,
                arguments: [available as CVarArg, percent as CVarArg])
        case "thermal-elevated":
            return String(format: localization.text(.evidenceThermal), thermalStateLabel(snapshot.thermal.state))
        case "memory-pressure":
            if let fraction = snapshot.memory.estimatedAvailableFraction {
                return String(
                    format: localization.text(.evidenceMemoryEstimated),
                    locale: localization.language.locale,
                    arguments: [Int((fraction * 100).rounded()) as CVarArg])
            }
            return localization.text(.evidenceMemoryFallback)
        case "cpu-busy":
            return String(
                format: localization.text(.evidenceCPU), locale: localization.language.locale,
                arguments: [85 as CVarArg, Int(snapshot.cpu.total.rounded()) as CVarArg])
        default:
            return finding.evidence
        }
    }

    private func thermalStateLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: localization.text(.nominal)
        case .fair: localization.text(.fair)
        case .serious: localization.text(.serious)
        case .critical: localization.text(.critical)
        @unknown default: localization.text(.unavailable)
        }
    }
}
