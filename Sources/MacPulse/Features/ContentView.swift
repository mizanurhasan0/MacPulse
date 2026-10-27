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
    @Namespace private var sidebarSelection

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 11) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MacPulse")
                            .font(.headline.weight(.bold))
                        Text(copy("MAC CLEANER", "ম্যাক ক্লিনার"))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 10)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 7) {
                    Text(copy("WORKSPACE", "ওয়ার্কস্পেস"))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 3)
                    pageRow(.cleaner, title: copy("Cleaner", "ক্লিনার"))
                    pageRow(.history, title: copy("Activity History", "অ্যাক্টিভিটি হিস্ট্রি"))
                    pageRow(.settings, title: copy("Settings", "সেটিংস"))
                }

                Spacer(minLength: 12)

                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy("Runs locally", "লোকালেই চলে"))
                            .font(.caption.weight(.semibold))
                        Text(copy("Your files stay on this Mac", "ফাইল এই Mac-এই থাকে"))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial)
            .navigationSplitViewColumnWidth(min: 205, ideal: 230, max: 270)
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
        SidebarNavigationRow(
            page: page,
            title: title,
            symbol: page.symbol,
            isSelected: selection == page,
            namespace: sidebarSelection) {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    selection = page
                }
            }
    }

    private func copy(_ english: String, _ bangla: String) -> String {
        localization.language == .bangla ? bangla : english
    }
}

private struct SidebarNavigationRow: View {
    let page: CleanerPage
    let title: String
    let symbol: String
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                    .symbolVariant(isSelected ? .fill : .none)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .scaleEffect(isSelected ? 1.06 : 1)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentColor.opacity(0.8))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(isHovered ? 0.045 : 0))
                    .matchedGeometryEffect(id: "sidebar-selection", in: namespace, isSource: isSelected)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 2)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nav.\(page.rawValue)")
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { isHovered = hovering }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isSelected)
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
        HStack(spacing: 12) {
            metricChip(
                title: bangla ? "CPU ব্যবহার" : "CPU usage",
                value: model.snapshot?.cpuPercent.map { "\(Int($0.rounded()))%" } ?? "—",
                symbol: "cpu",
                tint: model.snapshot?.cpuPercent.map { $0 >= 85 ? Color.orange : .green } ?? .secondary)
            metricChip(
                title: bangla ? "খালি জায়গা" : "Storage available",
                value: model.snapshot.map { ByteCountFormatter.string(fromByteCount: Int64($0.availableStorageBytes), countStyle: .file) } ?? "—",
                symbol: "internaldrive",
                tint: model.snapshot.map { $0.storageUsedFraction >= 0.9 ? .orange : .blue } ?? .secondary)
            metricChip(
                title: bangla ? "মোট RAM" : "Memory",
                value: model.snapshot.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0.totalMemoryBytes), countStyle: .memory) } ?? "—",
                symbol: "memorychip",
                tint: .purple)
            metricChip(
                title: bangla ? "তাপীয় অবস্থা" : "Thermal state",
                value: thermalLabel,
                symbol: "thermometer.medium",
                tint: thermalTint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }

    private var thermalLabel: String {
        switch model.snapshot?.thermalCondition ?? .unknown {
        case .normal: bangla ? "স্বাভাবিক" : "Normal"
        case .fair: bangla ? "মাঝারি" : "Fair"
        case .serious: bangla ? "উচ্চ" : "Serious"
        case .critical: bangla ? "গুরুতর" : "Critical"
        case .unknown: "—"
        }
    }

    private var thermalTint: Color {
        switch model.snapshot?.thermalCondition ?? .unknown {
        case .normal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        case .unknown: .secondary
        }
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
                                Text(folderCountLabel(group.entries.count))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: group.entries.reduce(UInt64(0)) { $0 &+ $1.estimatedBytes }), countStyle: .file))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Toggle(isOn: Binding(
                                get: { model.isCategorySelected(group.category) },
                                set: { model.selectCategory(group.category, selected: $0) })) {
                                    Text(bangla ? "সব ফোল্ডার" : "Select group")
                                        .font(.caption.weight(.medium))
                                }
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

    private func folderCountLabel(_ count: Int) -> String {
        if bangla { return "\(count)টি ফোল্ডার" }
        return count == 1 ? "1 folder" : "\(count) folders"
    }
}

private struct CleanupEntryRow: View {
    @EnvironmentObject private var model: CleanerModel
    let entry: CleanupEntry
    let bangla: Bool
    let isDisabled: Bool

    private var stateIcon: String? {
        switch entry.state {
        case .pending: nil
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
                if let stateIcon {
                    Image(systemName: stateIcon)
                        .foregroundStyle(stateColor)
                        .frame(width: 16)
                }
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
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(stateColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(stateColor.opacity(0.11), in: Capsule())
                    .frame(minWidth: 76, alignment: .trailing)
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
        case .pending: bangla ? "প্রস্তুত" : "Ready"
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
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 820
            let columns = isWide
                ? [GridItem(.flexible(), spacing: 18, alignment: .top), GridItem(.flexible(), spacing: 18, alignment: .top)]
                : [GridItem(.flexible(), alignment: .top)]

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    pageHeader
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                        if isWide {
                            appearanceCard
                            aboutCard
                            languageCard
                            privacyCard
                        } else {
                            appearanceCard
                            languageCard
                            privacyCard
                            aboutCard
                        }
                    }
                }
                .frame(maxWidth: 1260, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 30)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
    }

    private var pageHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.accent.color)
                .frame(width: 48, height: 48)
                .background(theme.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text(bangla ? "সেটিংস" : "Settings")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(bangla ? "অ্যাপের পছন্দ ও গোপনীয়তা নিয়ন্ত্রণ করুন" : "Personalize your workspace and privacy")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(bangla ? "এই Mac-এ" : "On this Mac", systemImage: "checkmark.shield.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.green.opacity(0.1), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appearanceCard: some View {
        settingsCard(
            symbol: "paintpalette.fill",
            tint: .purple,
            title: bangla ? "চেহারা" : "Appearance",
            subtitle: bangla ? "থিম ও অ্যাকসেন্ট রং বেছে নিন" : "Choose a theme and accent color") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(bangla ? "থিম" : "Theme")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 8) {
                            ForEach(AppearanceMode.allCases) { mode in
                                choiceButton(
                                    title: localization.text(mode.translationKey),
                                    symbol: themeSymbol(mode),
                                    isSelected: theme.appearance == mode) {
                                        theme.setAppearance(mode)
                                    }
                            }
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text(bangla ? "অ্যাকসেন্ট রং" : "Accent color")
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 8) {
                            ForEach(AccentPalette.allCases) { palette in
                                Button { theme.setAccent(palette) } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(palette.color)
                                            .frame(width: 13, height: 13)
                                            .overlay {
                                                if theme.accent == palette {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 8, weight: .heavy))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                        Text(localization.text(palette.translationKey))
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 9)
                                    .background(theme.accent == palette ? palette.color.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.accent == palette ? palette.color.opacity(0.4) : Color.primary.opacity(0.06)))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(localization.text(palette.translationKey))
                            }
                        }
                    }
                }
            }
    }

    private var languageCard: some View {
        settingsCard(
            symbol: "globe",
            tint: .blue,
            title: bangla ? "ভাষা" : "Language",
            subtitle: bangla ? "অ্যাপের প্রদর্শিত ভাষা নির্ধারণ করুন" : "Choose the language used throughout the app") {
                HStack(spacing: 10) {
                    ForEach(AppLanguage.allCases) { language in
                        choiceButton(
                            title: language.nativeName,
                            symbol: language == .english ? "textformat" : "character.book.closed",
                            isSelected: localization.language == language) {
                                localization.setLanguage(language)
                            }
                    }
                }
            }
    }

    private var privacyCard: some View {
        settingsCard(
            symbol: "lock.shield.fill",
            tint: .green,
            title: bangla ? "গোপনীয়তা" : "Privacy",
            subtitle: bangla ? "আপনার ফাইল আপনার Mac-এই থাকে" : "Your files stay on your Mac") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(bangla ? "লোকাল ক্লিনআপ" : "Local cleanup")
                            .font(.subheadline.weight(.semibold))
                        Text(bangla
                             ? "স্ক্যান ও পরিষ্কার এই ডিভাইসেই হয়। ফাইলের path অ্যাক্টিভিটি হিস্ট্রিতে সংরক্ষণ করা হয় না।"
                             : "Scanning and cleanup run on this device. File paths are never saved in activity history.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
    }

    private var aboutCard: some View {
        settingsCard(
            symbol: "info.circle.fill",
            tint: .orange,
            title: bangla ? "সম্পর্কে" : "About",
            subtitle: bangla ? "অ্যাপ ও সিস্টেমের তথ্য" : "App and system information") {
                VStack(spacing: 0) {
                    infoRow(
                        title: "MacPulse",
                        value: bangla ? "নেটিভ ম্যাক ক্লিনার" : "Native Mac cleaner",
                        symbol: "macwindow")
                    Divider().padding(.leading, 38)
                    infoRow(
                        title: "macOS",
                        value: ProcessInfo.processInfo.operatingSystemVersionString,
                        symbol: "desktopcomputer")
                    Divider().padding(.leading, 38)
                    infoRow(
                        title: bangla ? "ক্লিনার ইঞ্জিন" : "Cleaner engine",
                        value: bangla ? "অন্তর্নির্মিত" : "Built in",
                        symbol: "trash")
                }
            }
    }

    private func settingsCard<Content: View>(
        symbol: String,
        tint: Color,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.07)))
        .shadow(color: .black.opacity(0.035), radius: 12, y: 4)
    }

    private func choiceButton(
        title: String,
        symbol: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.caption.weight(.semibold))
                Text(title).font(.caption.weight(.medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? theme.accent.color : Color.primary.opacity(0.78))
            .background(isSelected ? theme.accent.color.opacity(0.12) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? theme.accent.color.opacity(0.4) : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private func themeSymbol(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    private func infoRow(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            Text(title).font(.callout.weight(.medium))
            Spacer(minLength: 12)
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 11)
    }
}
