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
    @State private var expandedGroups: Set<String> = []
    @State private var isProgressHovered = false
    @State private var hoveredGroup: String?
    @State private var scanAnimationStart: TimeInterval?
    @State private var scanPauseStart: TimeInterval?
    @State private var scanPausedDuration: TimeInterval = 0

    private var bangla: Bool { localization.language == .bangla }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                VStack(spacing: 12) {
                    topBar
                    cleanupDashboard(
                        availableWidth: geometry.size.width - 64,
                        availableHeight: geometry.size.height - 152)
                }
                .padding(14)
                .frame(maxWidth: 1680)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
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

    private func cleanupDashboard(availableWidth: CGFloat, availableHeight: CGFloat) -> some View {
        let contentWidth = max(0, availableWidth - 22)
        let progressWidth = min(580, max(220, contentWidth * 0.35))
        let panelHeight = max(320, min(600, availableHeight))
        let ringSize = min(350, max(170, min(progressWidth - 36, panelHeight - 185)))

        return HStack(spacing: 0) {
            progressPanel(ringSize: ringSize)
                .frame(width: progressWidth)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 20)
            folderSelectionPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: panelHeight)
        .background(
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.14, blue: 0.23), Color(nsColor: .underPageBackgroundColor)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.accentColor.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func progressPanel(ringSize: CGFloat) -> some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: model.stage != .scanning || model.isPaused)) { timeline in
                Button(action: progressControlTapped) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.09), style: StrokeStyle(lineWidth: 13, lineCap: .round))
                        Circle()
                            .trim(from: 0, to: scanArcLength(at: timeline.date))
                            .stroke(
                                AngularGradient(
                                    colors: [Color.accentColor.opacity(0.4), Color.cyan, Color.accentColor],
                                    center: .center),
                                style: StrokeStyle(lineWidth: 13, lineCap: .round))
                            .rotationEffect(.degrees(scanRotation(at: timeline.date)))
                            .animation(.spring(response: 0.52, dampingFraction: 0.88), value: ringProgress)

                        ringCenter
                            .transition(.opacity.combined(with: .scale(scale: 0.88)))
                    }
                    .animation(.easeInOut(duration: 0.32), value: model.stage)
                    .overlay {
                        if isProgressHovered {
                            Image(systemName: progressControlSymbol)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 58, height: 58)
                                .background(Color.accentColor.opacity(0.92), in: Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.24)))
                                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                                .transition(.scale(scale: 0.86).combined(with: .opacity))
                        }
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(width: ringSize, height: ringSize)
                .accessibilityIdentifier("cleaner.progressControl")
                .accessibilityLabel(progressControlAccessibilityLabel)
                .onHover { hovering in
                    withAnimation(.easeOut(duration: 0.16)) { isProgressHovered = hovering }
                }
                .animation(.easeOut(duration: 0.16), value: isProgressHovered)
            }

            VStack(spacing: 6) {
                Text(progressTitle)
                    .font(.system(size: ringSize >= 290 ? 30 : 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(progressSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var ringCenter: some View {
        if model.stage == .scanning {
            ProgressView()
                .controlSize(.regular)
                .tint(.white)
        } else if model.stage == .cleaning || model.cleanupIsComplete {
            VStack(spacing: 1) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.cyan)
                Text("\(Int((model.cleanupProgress * 100).rounded()))%")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
            }
        } else if model.hasScanResult {
            VStack(spacing: 1) {
                Text("\(model.selectedCount)")
                    .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                Text(bangla ? "নির্বাচিত" : "selected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        } else {
            Image(systemName: "trash.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Color.cyan)
        }
    }

    private var ringProgress: Double {
        if model.stage == .cleaning || model.cleanupIsComplete { return model.cleanupProgress }
        return model.hasScanResult ? 1 : 0.08
    }

    private func scanArcLength(at date: Date) -> Double {
        guard model.stage == .scanning else { return ringProgress }
        let elapsed = scanElapsed(at: date)
        let breathing = (sin(elapsed * 2.2) + 1) / 2
        return 0.12 + breathing * 0.18
    }

    private func scanRotation(at date: Date) -> Double {
        guard model.stage == .scanning else { return -90 }
        let elapsed = scanElapsed(at: date)
        return -90 - elapsed * 105
    }

    private func scanElapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSinceReferenceDate - (scanAnimationStart ?? date.timeIntervalSinceReferenceDate) - scanPausedDuration)
    }

    private var progressTitle: String {
        if model.isPaused { return bangla ? "কাজ বিরতিতে" : "Paused" }
        if model.stage == .scanning { return bangla ? "স্ক্যান চলছে" : "Scanning your Mac" }
        if model.stage == .cleaning { return bangla ? "ক্লিনিং চলছে" : "Cleaning in progress" }
        if model.cleanupIsComplete { return bangla ? "ক্লিনিং সম্পন্ন" : "Cleanup complete" }
        if model.hasScanResult { return bangla ? "ক্লিন করার জন্য প্রস্তুত" : "Ready to clean" }
        return bangla ? "স্ক্যানের জন্য প্রস্তুত" : "Ready to scan"
    }

    private var progressSubtitle: String {
        if model.isPaused { return bangla ? "চালিয়ে যেতে রিংয়ে চাপ দিন" : "Tap the ring to resume" }
        if model.stage == .scanning {
            return bangla ? "নিরাপদে পরিষ্কারযোগ্য ফোল্ডার খোঁজা হচ্ছে" : "Checking eligible cache and app folders"
        }
        if model.stage == .cleaning {
            return bangla
                ? "\(model.cleanupCompletedCount) / \(model.cleanupTotal)টি ফোল্ডার সম্পন্ন"
                : "\(model.cleanupCompletedCount) of \(model.cleanupTotal) folders complete"
        }
        if model.cleanupIsComplete {
            return bangla
                ? "\(model.cleanupCompletedCount)টি ফোল্ডার প্রসেস হয়েছে"
                : "\(model.cleanupCompletedCount) folders processed"
        }
        if model.hasScanResult {
            return model.entries.isEmpty
                ? (bangla ? "পরিষ্কার করার মতো ফোল্ডার পাওয়া যায়নি" : "No eligible folders were found")
                : (bangla
                    ? "\(model.selectedCount)টি ফোল্ডার · আনুমানিক \(formattedBytes(model.selectedBytes))"
                    : "\(model.selectedCount) folders · about \(formattedBytes(model.selectedBytes))")
        }
        return bangla ? "পরিষ্কারের আগে ফোল্ডারগুলো দেখে নিতে পারবেন" : "Review folders before anything is removed"
    }

    private var progressControlSymbol: String {
        if model.isBusy { return model.isPaused ? "play.fill" : "pause.fill" }
        if model.hasScanResult && !model.cleanupIsComplete && !model.entries.isEmpty { return "trash.fill" }
        if model.cleanupIsComplete { return "arrow.clockwise" }
        return "play.fill"
    }

    private var progressControlAccessibilityLabel: String {
        if model.isBusy {
            return model.isPaused
                ? (bangla ? "আবার চালু করুন" : "Resume")
                : (bangla ? "বিরতি দিন" : "Pause")
        }
        if model.hasScanResult && !model.cleanupIsComplete && !model.entries.isEmpty {
            return bangla ? "নির্বাচিত ফোল্ডার পরিষ্কার করুন" : "Clean selected folders"
        }
        return bangla ? "স্ক্যান শুরু করুন" : "Start scan"
    }

    private func progressControlTapped() {
        if model.isBusy {
            let now = Date.timeIntervalSinceReferenceDate
            if model.isPaused {
                if let scanPauseStart {
                    scanPausedDuration += now - scanPauseStart
                    self.scanPauseStart = nil
                }
            } else if model.stage == .scanning {
                scanPauseStart = now
            }
            model.togglePauseResume()
        } else if model.hasScanResult && !model.cleanupIsComplete && !model.entries.isEmpty {
            if model.selectedCount > 0 { showCleanConfirmation = true }
            else { model.cleanSelected() }
        } else {
            scanAnimationStart = Date.timeIntervalSinceReferenceDate
            scanPauseStart = nil
            scanPausedDuration = 0
            model.scanForCleanup()
        }
    }

    private func groupStatus(_ entries: [CleanupEntry]) -> (label: String, color: Color) {
        let selected = entries.filter(\.isSelected)
        guard !selected.isEmpty else { return (bangla ? "বাদ" : "Excluded", .secondary) }
        if selected.contains(where: { $0.state == .cleaning }) {
            return (bangla ? "চলছে" : "Cleaning", .cyan)
        }
        if model.stage == .cleaning && selected.contains(where: { $0.state == .pending }) {
            return (bangla ? "অপেক্ষায়" : "Queued", .secondary)
        }
        if selected.contains(where: { $0.state == .pending }) {
            return (bangla ? "প্রস্তুত" : "Ready", Color.accentColor)
        }
        if selected.contains(where: { $0.state == .retained }) {
            return (bangla ? "কিছু বাদ" : "Partial", .orange)
        }
        return (bangla ? "সম্পন্ন" : "Done", .green)
    }

    private func statusChip(_ label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
        .fixedSize()
    }

    private func categoryDescription(_ category: String, count: Int) -> String {
        let lowercased = category.lowercased()
        if lowercased.contains("browser") {
            return bangla ? "ব্রাউজারের ক্যাশ · \(folderCountLabel(count))" : "Browser temporary data · \(folderCountLabel(count))"
        }
        if lowercased.contains("developer") || lowercased.contains("xcode") || lowercased.contains("simulator") {
            return bangla ? "বিল্ড ও প্যাকেজ ক্যাশ · \(folderCountLabel(count))" : "Build and package caches · \(folderCountLabel(count))"
        }
        if lowercased.contains("homebrew") {
            return bangla ? "প্যাকেজ ডাউনলোড · \(folderCountLabel(count))" : "Package downloads · \(folderCountLabel(count))"
        }
        if lowercased.contains("log") {
            return bangla ? "অ্যাপের পুরোনো লগ · \(folderCountLabel(count))" : "Older application logs · \(folderCountLabel(count))"
        }
        return bangla ? "অ্যাপ ও সার্ভিসের ক্যাশ · \(folderCountLabel(count))" : "Caches from apps and services · \(folderCountLabel(count))"
    }

    private var folderSelectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bangla ? "নির্বাচিত ফোল্ডার" : "Selected folders")
                        .font(.headline)
                    Text(model.hasScanResult
                         ? (bangla ? "\(model.displayedSelectedCount) / \(model.entries.count) নির্বাচিত" : "\(model.displayedSelectedCount) of \(model.entries.count) selected")
                         : (bangla ? "স্ক্যানের পর ফোল্ডার দেখা যাবে" : "Folders appear after scanning"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if model.hasScanResult && !model.entries.isEmpty {
                    Toggle(bangla ? "সব নির্বাচন" : "Select all", isOn: Binding(
                        get: { model.areAllEntriesSelected },
                        set: { model.selectAll($0) }))
                        .toggleStyle(.checkbox)
                        .disabled(model.isBusy || model.pendingCount == 0)
                        .fixedSize()
                }
            }

            if !model.hasScanResult {
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Image(systemName: model.stage == .scanning ? "magnifyingglass" : "folder.badge.questionmark")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.85))
                        .frame(width: 58, height: 58)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 17))
                    Text(model.stage == .scanning
                         ? (bangla ? "ফোল্ডার স্ক্যান হচ্ছে" : "Scanning cleanup locations")
                         : (bangla ? "আগে স্ক্যান চালান" : "Run a scan to review folders"))
                        .font(.callout.weight(.semibold))
                    Text(model.stage == .scanning
                         ? (model.logLines.last?.text ?? (bangla ? "ফোল্ডারের তথ্য পরীক্ষা করা হচ্ছে" : "Checking folder contents"))
                         : (bangla ? "কোন ফোল্ডারগুলো পরিষ্কার হবে তা আগে দেখে ও বেছে নিতে পারবেন।" : "You’ll be able to inspect and choose folders before cleaning."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else if model.entries.isEmpty {
                Spacer(minLength: 0)
                ContentUnavailableView(
                    bangla ? "ক্লিন করার কিছু নেই" : "Nothing to clean",
                    systemImage: "checkmark.circle",
                    description: Text(bangla ? "নিরাপদে পরিষ্কার করার মতো ফোল্ডার পাওয়া যায়নি।" : "No eligible cleanup folders were found."))
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(groupedEntries, id: \.category) { group in
                            let expanded = expandedGroups.contains(group.category)
                            let status = groupStatus(group.entries)
                            VStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    Button {
                                        model.selectCategory(
                                            group.category,
                                            selected: !model.isCategorySelected(group.category))
                                    } label: {
                                        Image(systemName: model.isCategorySelected(group.category)
                                              ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 17, weight: .semibold))
                                            .foregroundStyle(model.isCategorySelected(group.category)
                                                             ? Color.accentColor : Color.secondary.opacity(0.8))
                                            .frame(width: 24, height: 48, alignment: .center)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(model.isBusy || model.pendingCount == 0)
                                    .accessibilityLabel(model.isCategorySelected(group.category)
                                                        ? (bangla ? "গ্রুপ থেকে বাদ দিন" : "Deselect group")
                                                        : (bangla ? "গ্রুপ নির্বাচন করুন" : "Select group"))

                                    Button {
                                        toggleGroup(group.category)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.tertiary)
                                                .rotationEffect(.degrees(expanded ? 90 : 0))
                                                .frame(width: 14, height: 32)
                                            Image(systemName: categorySymbol(group.category))
                                                .font(.callout.weight(.semibold))
                                                .foregroundStyle(categoryColor(group.category))
                                                .frame(width: 32, height: 32)
                                                .background(categoryColor(group.category).opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(group.category)
                                                    .font(.callout.weight(.semibold))
                                                    .lineLimit(1)
                                                Text(categoryDescription(group.category, count: group.entries.count))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            statusChip(status.label, tint: status.color)
                                            Text(formattedBytes(group.entries.reduce(UInt64(0)) { $0 &+ $1.estimatedBytes }))
                                                .font(.caption.monospacedDigit().weight(.medium))
                                                .foregroundStyle(.secondary)
                                                .frame(minWidth: 64, alignment: .trailing)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityLabel(expanded
                                                        ? (bangla ? "ফোল্ডার লুকান: \(group.category)" : "Collapse \(group.category)")
                                                        : (bangla ? "ফোল্ডার দেখান: \(group.category)" : "Expand \(group.category)"))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)

                                if expanded {
                                    VStack(spacing: 0) {
                                        ForEach(group.entries) { entry in
                                            Divider().padding(.leading, 51)
                                            CleanupEntryRow(
                                                entry: entry,
                                                bangla: bangla,
                                                isDisabled: model.isBusy || entry.state != .pending)
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.horizontal, 5)
                            .background(Color.white.opacity(hoveredGroup == group.category ? 0.065 : 0.035), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(hoveredGroup == group.category ? 0.09 : 0.04)))
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                            .onHover { hovering in
                                withAnimation(.easeOut(duration: 0.16)) {
                                    hoveredGroup = hovering ? group.category : nil
                                }
                            }
                            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: expanded)
                            .animation(.easeOut(duration: 0.16), value: hoveredGroup)
                        }
                    }
                    .padding(.trailing, 3)
                }
                .scrollIndicators(.hidden)
            }

            dashboardProgressFooter
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var dashboardProgressFooter: some View {
        if model.stage == .cleaning || model.cleanupIsComplete {
            VStack(alignment: .leading, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule()
                            .fill(LinearGradient(colors: [.cyan, Color.accentColor], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geometry.size.width * model.cleanupProgress)
                    }
                }
                .frame(height: 10)
                HStack(spacing: 5) {
                    Text("\(Int((model.cleanupProgress * 100).rounded()))% \(bangla ? "সম্পন্ন" : "complete")")
                        .fontWeight(.semibold)
                    Text("· \(formattedBytes(model.estimatedCleanedBytes)) \(bangla ? "আনুমানিক পরিষ্কার" : "estimated cleaned")")
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospacedDigit())
            }
            .padding(.top, 7)
        } else if model.hasScanResult && !model.entries.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive")
                    .foregroundStyle(.cyan)
                Text(bangla ? "আনুমানিক পরিষ্কারযোগ্য" : "Estimated to reclaim")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedBytes(model.selectedBytes))
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .font(.caption)
            .padding(.top, 6)
        }
    }

    private func formattedBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
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
        .padding(2)
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

    private var groupedEntries: [(category: String, entries: [CleanupEntry])] {
        Dictionary(grouping: model.entries, by: \.category)
            .map { (category: $0.key, entries: $0.value.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }) }
            .sorted { $0.category.localizedStandardCompare($1.category) == .orderedAscending }
    }

    private func toggleGroup(_ category: String) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            if expandedGroups.contains(category) {
                expandedGroups.remove(category)
            } else {
                expandedGroups.insert(category)
            }
        }
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
        case .cleaning: "arrow.triangle.2.circlepath"
        case .removed: "checkmark.circle.fill"
        case .retained: "minus.circle"
        }
    }
    private var stateColor: Color {
        switch entry.state {
        case .pending: .secondary
        case .cleaning: .cyan
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
        case .cleaning: bangla ? "পরিষ্কার হচ্ছে" : "Cleaning"
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
