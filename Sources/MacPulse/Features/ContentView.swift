import SwiftUI

private enum CleanerPage: String, CaseIterable, Identifiable {
    case cleaner, history, settings
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cleaner: "trash"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: CleanerModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var selection: CleanerPage? = .cleaner

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    pageRow(.cleaner, title: copy("Cleaner", "ক্লিনার"))
                    pageRow(.history, title: copy("Activity History", "অ্যাক্টিভিটি হিস্ট্রি"))
                    pageRow(.settings, title: copy("Settings", "সেটিংস"))
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("MacPulse")
            .navigationSplitViewColumnWidth(min: 185, ideal: 210, max: 250)
        } detail: {
            Group {
                switch selection ?? .cleaner {
                case .cleaner: CleanerHomeView()
                case .history: ActivityHistoryView()
                case .settings: CleanerSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.locale, localization.language.locale)
        .environment(\.layoutDirection, localization.layoutDirection)
        .task { model.startMonitoring() }
        .onDisappear { model.stopMonitoring() }
        .alert(copy("Cleanup issue", "ক্লিন করতে সমস্যা"), isPresented: Binding(
            get: { model.lastError != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button(copy("OK", "ঠিক আছে")) { model.clearError() }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private func pageRow(_ page: CleanerPage, title: String) -> some View {
        Label(title, systemImage: page.symbol)
            .padding(.vertical, 5)
            .tag(page)
            .accessibilityIdentifier("nav.\(page.rawValue)")
    }

    private func copy(_ english: String, _ bangla: String) -> String {
        localization.language == .bangla ? bangla : english
    }
}

private struct CleanerHomeView: View {
    @EnvironmentObject private var model: CleanerModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var showCleanConfirmation = false

    private var bangla: Bool { localization.language == .bangla }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 30)
                .padding(.top, 22)
                .padding(.bottom, 18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    if model.isBusy || !model.logLines.isEmpty {
                        activityPanel
                    }
                    if model.hasScanResult {
                        selectionSummary
                    }
                    if !model.entries.isEmpty {
                        fileList
                    } else if model.hasScanResult && !model.isBusy {
                        ContentUnavailableView(
                            bangla ? "ক্লিন করার কিছু নেই" : "Nothing to clean",
                            systemImage: "checkmark.circle",
                            description: Text(bangla ? "নিরাপদে পরিষ্কার করার মতো কোনো ফোল্ডার পাওয়া যায়নি।" : "No eligible folders were found."))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 1000, alignment: .leading)
                .padding(30)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await model.refreshMetrics() }
        .confirmationDialog(
            bangla ? "এই ফোল্ডারগুলো পরিষ্কার করবেন?" : "Clean these folders?",
            isPresented: $showCleanConfirmation,
            titleVisibility: .visible) {
                Button(bangla ? "এখনই পরিষ্কার করুন" : "Clean now", role: .destructive) {
                    model.cleanSelected()
                }
                Button(bangla ? "বাতিল" : "Cancel", role: .cancel) {}
            } message: {
                Text(model.confirmationSummary)
            }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bangla ? "ম্যাক ক্লিনার" : "Mac Cleaner")
                    .font(.title2.bold())
                Text(bangla ? "আপনার Mac-এর জন্য সহজ ও স্বচ্ছ ক্লিনার" : "A clear, built-in cleaner for your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            metricChip(
                title: bangla ? "CPU health" : "CPU health",
                value: model.snapshot?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—",
                symbol: "cpu",
                tint: model.snapshot?.cpuPercent.map { $0 >= 85 ? Color.orange : .green } ?? .secondary)
            metricChip(
                title: bangla ? "খালি জায়গা" : "Storage available",
                value: model.snapshot.map { ByteCountFormatter.string(fromByteCount: Int64($0.availableStorageBytes), countStyle: .file) } ?? "—",
                symbol: "internaldrive",
                tint: model.snapshot.map { $0.storageUsedFraction >= 0.9 ? .orange : .blue } ?? .secondary)
        }
    }

    private func metricChip(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.callout.weight(.semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.callout.weight(.semibold).monospacedDigit())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private var selectionSummary: some View {
        HStack(spacing: 12) {
            summaryTile(
                title: bangla ? "নির্বাচিত ফোল্ডার" : "Selected folders",
                value: "\(model.selectedCount) / \(model.pendingCount)",
                symbol: "folder.badge.checkmark",
                tint: .indigo)
            summaryTile(
                title: bangla ? "আনুমানিক জায়গা" : "Estimated space",
                value: ByteCountFormatter.string(fromByteCount: Int64(clamping: model.selectedBytes), countStyle: .file),
                symbol: "externaldrive.badge.checkmark",
                tint: .green)
            Spacer(minLength: 4)
            Toggle(bangla ? "সব নির্বাচন" : "Select all", isOn: Binding(
                get: { model.pendingCount > 0 && model.selectedCount == model.pendingCount },
                set: { model.selectAll($0) }))
                .toggleStyle(.checkbox)
                .disabled(model.isBusy || model.pendingCount == 0)
                .fixedSize()
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }

    private func summaryTile(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.callout.weight(.semibold).monospacedDigit())
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Image(systemName: model.isBusy ? "arrow.trianglehead.2.clockwise.rotate.90" : "trash.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 66, height: 66)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 20))
            VStack(spacing: 6) {
                Text(model.hasScanResult
                     ? (bangla ? "কী পরিষ্কার হবে বেছে নিন" : "Review what will be cleaned")
                     : (bangla ? "ম্যাক পরিষ্কার করুন" : "Clean your Mac"))
                    .font(.largeTitle.bold())
                Text(bangla
                     ? "আগে ফোল্ডারগুলো দেখে নিন, তারপর যেগুলো চান সেগুলো পরিষ্কার করুন।"
                     : "Review the folders first, then clean only what you choose.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                if model.hasScanResult {
                    if model.selectedCount > 0 { showCleanConfirmation = true }
                    else { model.cleanSelected() }
                } else {
                    model.scanForCleanup()
                }
            } label: {
                HStack(spacing: 10) {
                    if model.isBusy { ProgressView().controlSize(.small) }
                    else { Image(systemName: model.hasScanResult ? "trash.fill" : "magnifyingglass") }
                    Text(model.isBusy
                         ? (model.stage == .scanning
                            ? (bangla ? "ফাইল স্ক্যান হচ্ছে…" : "Scanning files…")
                            : (bangla ? "ফাইল পরিষ্কার হচ্ছে…" : "Cleaning files…"))
                         : (model.hasScanResult
                            ? (bangla ? "নির্বাচিতগুলো পরিষ্কার · \(model.selectedCount)" : "Clean selected · \(model.selectedCount)")
                            : (bangla ? "স্ক্যান শুরু করুন" : "Scan for cleanup")))
                }
                .font(.headline)
                .frame(minWidth: 215)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isBusy || (model.hasScanResult && model.selectedCount == 0))
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("cleaner.run")
            if model.hasScanResult {
                Button(bangla ? "আবার স্ক্যান" : "Scan again", action: model.scanForCleanup)
                    .buttonStyle(.link)
                    .disabled(model.isBusy)
            }
            if let result = model.lastResult {
                Text(result).font(.callout.weight(.medium)).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 27)
        .padding(.horizontal, 22)
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.09), Color.accentColor.opacity(0.025)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.accentColor.opacity(0.12)))
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(bangla ? "লাইভ প্রক্রিয়া" : "Live process")
                    .font(.headline)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(model.logLines) { row in
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(row.isWarning ? Color.orange : Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(row.text)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(row.isWarning ? .orange : .secondary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .id(row.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(190, max(72, CGFloat(model.logLines.count) * 21)))
                .onChange(of: model.logLines.count) { _, _ in
                    if let last = model.logLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Label(bangla ? "পরিষ্কারের ফোল্ডার" : "Cleanup folders", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Text(bangla ? "\(groupedEntries.count)টি গ্রুপ" : "\(groupedEntries.count) groups")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                ForEach(groupedEntries, id: \.category) { group in
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: categorySymbol(group.category))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(categoryColor(group.category))
                                .frame(width: 30, height: 30)
                                .background(categoryColor(group.category).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.category).font(.callout.weight(.semibold))
                                Text(bangla ? "\(group.entries.count)টি ফোল্ডার" : "\(group.entries.count) folders")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: group.entries.reduce(UInt64(0)) { $0 &+ $1.estimatedBytes }), countStyle: .file))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Toggle(group.category, isOn: Binding(
                                get: { model.isCategorySelected(group.category) },
                                set: { model.selectCategory(group.category, selected: $0) }))
                                .labelsHidden()
                                .toggleStyle(.checkbox)
                                .disabled(model.isBusy || group.entries.allSatisfy { $0.state != .pending })
                                .accessibilityLabel(bangla ? "এই গ্রুপ নির্বাচন" : "Select this group")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)

                        ForEach(group.entries) { entry in
                            Divider().padding(.leading, 54)
                            CleanupEntryRow(
                                entry: entry,
                                bangla: bangla,
                                isDisabled: model.isBusy || entry.state != .pending)
                        }
                    }
                    .background(.background, in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.quaternary))
                }
            }
        }
    }

    private var groupedEntries: [(category: String, entries: [CleanupEntry])] {
        Dictionary(grouping: model.entries, by: \.category)
            .map { (category: $0.key, entries: $0.value.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }) }
            .sorted { $0.category.localizedStandardCompare($1.category) == .orderedAscending }
    }

    private func categorySymbol(_ category: String) -> String {
        let value = category.lowercased()
        if value.contains("browser") { return "safari" }
        if value.contains("developer") || value.contains("xcode") || value.contains("simulator") { return "hammer.fill" }
        if value.contains("log") { return "doc.text" }
        if value.contains("temporary") { return "clock" }
        if value.contains("editor") || value.contains("app cache") { return "square.stack.3d.up" }
        return "folder.fill"
    }

    private func categoryColor(_ category: String) -> Color {
        let value = category.lowercased()
        if value.contains("browser") { return .blue }
        if value.contains("developer") || value.contains("xcode") || value.contains("simulator") { return .orange }
        if value.contains("log") { return .purple }
        if value.contains("temporary") { return .teal }
        return .indigo
    }
}

private struct CleanupEntryRow: View {
    @EnvironmentObject private var model: CleanerModel
    let entry: CleanupEntry
    let bangla: Bool
    let isDisabled: Bool

    private var stateIcon: String {
        switch entry.state {
        case .pending: "circle"
        case .removed: "checkmark.circle.fill"
        case .retained: "minus.circle"
        }
    }
    private var stateColor: Color {
        switch entry.state {
        case .pending: .secondary
        case .removed: .green
        case .retained: .orange
        }
    }

    var body: some View {
        Toggle(isOn: Binding(
            get: { entry.isSelected },
            set: { model.setEntry(entry.url.path, selected: $0) })) {
            HStack(spacing: 10) {
                Image(systemName: stateIcon).foregroundStyle(stateColor).frame(width: 16)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.url.lastPathComponent)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(entry.url.deletingLastPathComponent().path)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if entry.estimatedBytes > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: entry.estimatedBytes), countStyle: .file))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 62, alignment: .trailing)
                }
                Text(stateLabel)
                    .font(.caption2)
                    .foregroundStyle(stateColor)
                    .frame(width: 78, alignment: .trailing)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isDisabled)
        .padding(.horizontal, 13)
        .padding(.leading, 26)
        .padding(.vertical, 9)
    }

    private var stateLabel: String {
        switch entry.state {
        case .pending: bangla ? "অপেক্ষায়" : "Waiting"
        case .removed: bangla ? "মুছে গেছে" : "Removed"
        case .retained: bangla ? "রয়ে গেছে" : "Kept"
        }
    }
}

private struct ActivityHistoryView: View {
    @EnvironmentObject private var model: CleanerModel
    @EnvironmentObject private var localization: LocalizationStore
    @State private var confirmingClear = false
    private var bangla: Bool { localization.language == .bangla }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(bangla ? "অ্যাক্টিভিটি হিস্ট্রি" : "Activity History").font(.largeTitle.bold())
                    Text(bangla ? "সাম্প্রতিক cleanup-এর সারাংশ" : "Recent cleanup summaries")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.activityRecords.isEmpty {
                    Button(bangla ? "ইতিহাস মুছুন" : "Clear history", role: .destructive) {
                        confirmingClear = true
                    }
                    .buttonStyle(.bordered)
                }
            }
            if model.activityRecords.isEmpty {
                ContentUnavailableView(
                    bangla ? "কোনো ইতিহাস নেই" : "No activity yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(bangla ? "তোমার cleanup-এর ফল এখানে দেখা যাবে।" : "Cleanup results will appear here."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.activityRecords) { record in HistoryRecordRow(record: record, bangla: bangla) }
                    }
                    .padding(.bottom, 16)
                }
            }
            Text(bangla ? "ইতিহাসে শুধু সময়, ফলাফল ও item-এর সংখ্যা থাকে; ফাইলের path রাখা হয় না।" : "History stores time, result, and item count. File paths are never saved.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .confirmationDialog(
            bangla ? "সব ইতিহাস মুছবেন?" : "Clear all activity history?",
            isPresented: $confirmingClear, titleVisibility: .visible) {
                Button(bangla ? "ইতিহাস মুছুন" : "Clear history", role: .destructive) { model.clearHistory() }
                Button(bangla ? "বাতিল" : "Cancel", role: .cancel) {}
            }
    }
}

private struct HistoryRecordRow: View {
    let record: ActivityRecord
    let bangla: Bool

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: record.status == .completed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3).foregroundStyle(record.status == .completed ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(summary).font(.callout.weight(.semibold))
                Text(record.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(bangla ? "\(record.count)টি item" : "\(record.count) items")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if let delta = record.availableStorageDelta {
                Text((delta >= 0 ? "+" : "−") + ByteCountFormatter.string(fromByteCount: Int64(clamping: delta.magnitude), countStyle: .file))
                    .font(.caption.monospacedDigit()).foregroundStyle(delta > 0 ? .green : .secondary)
            }
        }
        .padding(15)
        .background(.background, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.quaternary))
    }

    private var summary: String {
        guard record.kind == .cleanerCleanup else {
            let saved = record.safeSummary
            return saved == "Activity recorded"
                ? (bangla ? "আগের অ্যাক্টিভিটি" : "Previous activity") : saved
        }
        return switch record.status {
        case .completed: bangla ? "ক্লিনিং সম্পন্ন" : "Cleanup completed"
        case .partial: bangla ? "কিছু item বাদ গেছে" : "Cleanup completed with skipped items"
        case .failed: bangla ? "ক্লিনিং ব্যর্থ" : "Cleanup failed"
        case .cancelled: bangla ? "বাতিল" : "Cancelled"
        case .requested: bangla ? "অনুরোধ পাঠানো হয়েছে" : "Request sent"
        case .notAccepted: bangla ? "অনুরোধ গ্রহণ করা হয়নি" : "Request not accepted"
        }
    }
}

private struct CleanerSettingsView: View {
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var theme: ThemeStore
    private var bangla: Bool { localization.language == .bangla }

    var body: some View {
        Form {
            Section(bangla ? "চেহারা" : "Appearance") {
                Picker(bangla ? "থিম" : "Theme", selection: Binding(
                    get: { theme.appearance }, set: { theme.setAppearance($0) })) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(localization.text(mode.translationKey)).tag(mode)
                        }
                    }
                Picker(bangla ? "অ্যাকসেন্ট রং" : "Accent color", selection: Binding(
                    get: { theme.accent }, set: { theme.setAccent($0) })) {
                        ForEach(AccentPalette.allCases) { palette in
                            Text(localization.text(palette.translationKey)).tag(palette)
                        }
                    }
            }
            Section(bangla ? "ভাষা" : "Language") {
                Picker(bangla ? "অ্যাপের ভাষা" : "App language", selection: Binding(
                    get: { localization.language }, set: { localization.setLanguage($0) })) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language)
                        }
                    }
            }
            Section(bangla ? "গোপনীয়তা" : "Privacy") {
                Label(
                    bangla ? "ক্লিনআপ এই Mac-এ চলে। ফাইলের path ইতিহাসে রাখা হয় না।" : "Cleanup runs on this Mac. File paths are not stored in history.",
                    systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            }
            Section(bangla ? "সম্পর্কে" : "About") {
                LabeledContent(bangla ? "macOS" : "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent(bangla ? "ক্লিনার" : "Cleaner", value: "Built in")
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(bangla ? "সেটিংস" : "Settings")
    }
}
