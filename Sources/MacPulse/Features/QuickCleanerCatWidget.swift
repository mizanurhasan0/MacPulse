import AppKit
import SwiftUI

/// A separate, lightweight floating window. The mascot uses SwiftUI shapes,
/// so it adds no image or animation files to the app bundle.
struct QuickCleanerCatWidget: View {
    let onExpand: () -> Void
    let onResize: (CGSize) -> Void
    @EnvironmentObject private var model: CleanerModel
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var isBreathing = false
    @State private var awaitingQuickScan = false
    @State private var showClearConfirmation = false
    @State private var resultMessage: String?

    private var bangla: Bool { localization.language == .bangla }
    private var panelWidth: CGFloat { isExpanded ? 264 : 76 }
    private var panelHeight: CGFloat {
        guard isExpanded else { return 88 }
        if model.cleanupIsComplete && model.skippedCount > 0 { return 304 }
        return resultMessage == nil ? 184 : 218
    }
    private var panelSize: CGSize { CGSize(width: panelWidth, height: panelHeight) }

    var body: some View {
        Group {
            if isExpanded {
                expandedWidget
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            } else {
                catButton
                    .transition(.scale(scale: 0.86).combined(with: .opacity))
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .background(Color.clear)
        .preferredColorScheme(theme.appearance.colorScheme)
        .tint(theme.accent.color)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isExpanded)
        .onAppear {
            model.startMonitoring()
            onResize(panelSize)
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isBreathing = true
                }
            }
        }
        .onChange(of: panelSize) { _, size in onResize(size) }
        .onChange(of: model.stage) { oldStage, newStage in
            guard awaitingQuickScan, oldStage == .scanning, newStage == .idle else { return }
            awaitingQuickScan = false
            if model.hasScanResult, !model.entries.isEmpty {
                showClearConfirmation = true
            } else {
                resultMessage = bangla ? "মুছার মতো ক্যাশে পাওয়া যায়নি" : "No eligible caches found"
            }
        }
        .onChange(of: model.cleanupIsComplete) { _, complete in
            guard complete else { return }
            let removed = max(0, model.cleanupCompletedCount - model.skippedCount)
            resultMessage = bangla
                ? "\(removed)টি ক্যাশে মুছে ফেলা হয়েছে · \(model.skippedCount)টি বাদ"
                : "\(removed) cleared · \(model.skippedCount) skipped"
        }
        .confirmationDialog(
            bangla ? "নির্বাচিত ক্যাশে মুছবেন?" : "Clear eligible caches?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible) {
                Button(bangla ? "ক্যাশে মুছুন" : "Clear caches", role: .destructive) {
                    resultMessage = nil
                    model.cleanSelected()
                }
                Button(bangla ? "বাতিল" : "Cancel", role: .cancel) {}
            } message: {
                Text(model.confirmationSummary)
            }
    }

    private var catButton: some View {
        CatMascot(size: 72)
                .scaleEffect(isBreathing ? 1.035 : 0.98)
                .frame(width: 76, height: 88)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 3)
                .overlay {
                    CompanionDragHandle(
                        label: bangla ? "কুইক ক্লিনার খুলুন" : "Open quick cleaner",
                        help: bangla ? "ক্লিক করে খুলুন, টেনে সরান" : "Click to open; drag to move") {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                                isExpanded = true
                            }
                        }
                }
    }

    private var expandedWidget: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                CatMascot(size: 36)
                    .frame(width: 39, height: 38)
                    .overlay {
                        CompanionDragHandle(
                            label: bangla ? "বিড়ালে ফিরুন" : "Back to cat",
                            help: bangla ? "ক্লিক করে ছোট করুন, টেনে সরান" : "Click to collapse; drag to move") {
                                isExpanded = false
                            }
                    }
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, height: 32)
                    .overlay {
                        CompanionDragHandle(
                            label: bangla ? "টেনে সরান" : "Drag to move",
                            help: bangla ? "এই উইন্ডোটি টেনে সরান" : "Drag this window to move it")
                    }
                Spacer(minLength: 4)
                Button {
                    isExpanded = false
                    onExpand()
                } label: {
                    Image(systemName: "macwindow")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(bangla ? "Cleaner উইন্ডো খুলুন" : "Open Cleaner window")
                .accessibilityLabel(bangla ? "Cleaner উইন্ডো খুলুন" : "Expand to Cleaner window")

            }

            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bangla ? "খালি স্টোরেজ" : "Available space")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(availableStorage)
                        .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))

            Button(action: startQuickClear) {
                HStack(spacing: 8) {
                    if model.isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(clearButtonTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    if !model.isBusy {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .foregroundStyle(.white)
                .background(model.isBusy ? Color.secondary : Color.accentColor, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .disabled(model.isBusy || awaitingQuickScan)
            .accessibilityIdentifier("quickCleaner.clear")

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            if model.cleanupIsComplete && model.skippedCount > 0 {
                Text(bangla
                     ? "অ্যাক্সেসের কারণে কিছু বাদ পড়লে Privacy & Security-তে অনুমতি দিন, তারপর আবার Clear চাপুন।"
                     : "If access blocked these items, allow it in Privacy & Security, then press Clear again.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: openPrivacySettings) {
                    Label(bangla ? "সেটিংসে অ্যাক্সেস দেখুন" : "Open Privacy & Security", systemImage: "lock.open")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
        .padding(14)
        .frame(width: 264, alignment: .leading)
        .background(widgetSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.09)))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.14), radius: 20, y: 8)
    }

    private var widgetSurface: Color {
        colorScheme == .dark
            ? Color(nsColor: .windowBackgroundColor)
            : Color(nsColor: .controlBackgroundColor)
    }

    private var availableStorage: String {
        guard let bytes = model.snapshot?.availableStorageBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private var clearButtonTitle: String {
        if model.stage == .scanning { return bangla ? "স্ক্যান হচ্ছে…" : "Scanning…" }
        if model.stage == .cleaning { return bangla ? "পরিষ্কার হচ্ছে…" : "Clearing…" }
        return bangla ? "ক্যাশে মুছুন" : "Clear caches"
    }

    private func startQuickClear() {
        guard !model.isBusy else { return }
        resultMessage = nil
        awaitingQuickScan = true
        model.scanForCleanup()
    }

    private func openPrivacySettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

}

private struct CatMascot: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tailSway = false
    @State private var blinking = false
    private let fur = Color(red: 0.94, green: 0.57, blue: 0.24)
    private let cream = Color(red: 1.0, green: 0.91, blue: 0.73)
    private let ink = Color(red: 0.24, green: 0.19, blue: 0.18)

    var body: some View {
        ZStack {
            tail
            Ellipse().fill(fur.gradient)
                .frame(width: size * 0.53, height: size * 0.56)
                .offset(y: size * 0.19)
            Ellipse().fill(cream)
                .frame(width: size * 0.31, height: size * 0.35)
                .offset(y: size * 0.23)
            HStack(spacing: size * 0.06) {
                Capsule().fill(cream)
                Capsule().fill(cream)
            }
            .frame(width: size * 0.49, height: size * 0.13)
            .offset(y: size * 0.43)
            head.offset(y: -size * 0.14)
            Capsule().fill(Color(red: 0.12, green: 0.59, blue: 0.58))
                .frame(width: size * 0.40, height: size * 0.055)
                .offset(y: size * 0.12)
            Circle().fill(Color(red: 1.0, green: 0.77, blue: 0.30))
                .frame(width: size * 0.085, height: size * 0.085)
                .offset(y: size * 0.17)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                tailSway = true
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4))
                    withAnimation(.easeInOut(duration: 0.12)) { blinking = true }
                    try await Task.sleep(for: .milliseconds(160))
                    withAnimation(.easeInOut(duration: 0.12)) { blinking = false }
                } catch { break }
            }
        }
    }

    private var tail: some View {
        Path { path in
            path.move(to: CGPoint(x: size * 0.62, y: size * 0.86))
            path.addCurve(
                to: CGPoint(x: size * 0.83, y: size * 0.52),
                control1: CGPoint(x: size * 1.00, y: size * 1.02),
                control2: CGPoint(x: size * 0.99, y: size * 0.58))
        }
        .stroke(fur, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
        .rotationEffect(.degrees(tailSway ? 5 : -7), anchor: .bottom)
    }

    private var head: some View {
        ZStack {
            HStack(spacing: size * 0.19) {
                Triangle().fill(fur)
                Triangle().fill(fur)
            }
            .frame(width: size * 0.66, height: size * 0.34)
            .offset(y: -size * 0.23)
            HStack(spacing: size * 0.27) {
                Triangle().fill(Color(red: 0.91, green: 0.51, blue: 0.48))
                Triangle().fill(Color(red: 0.91, green: 0.51, blue: 0.48))
            }
            .frame(width: size * 0.57, height: size * 0.22)
            .offset(y: -size * 0.22)
            Ellipse().fill(fur.gradient)
                .frame(width: size * 0.74, height: size * 0.55)
            Ellipse().fill(cream)
                .frame(width: size * 0.43, height: size * 0.24)
                .offset(y: size * 0.13)
            HStack(spacing: size * 0.25) {
                eye
                eye
            }
            .offset(y: size * 0.005)
            Triangle().fill(ink)
                .frame(width: size * 0.10, height: size * 0.07)
                .rotationEffect(.degrees(180))
                .offset(y: size * 0.105)
            Path { path in
                for side in [-1.0, 1.0] {
                    for row in [0.12, 0.19] {
                        path.move(to: CGPoint(x: size * (0.5 + side * 0.20), y: size * (0.5 + row)))
                        path.addLine(to: CGPoint(x: size * (0.5 + side * 0.38), y: size * (0.5 + row - 0.025)))
                    }
                }
            }
            .stroke(ink.opacity(0.6), style: StrokeStyle(lineWidth: max(0.7, size * 0.012), lineCap: .round))
        }
    }

    private var eye: some View {
        Ellipse().fill(ink)
            .frame(width: size * 0.09, height: size * 0.12)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white)
                    .frame(width: size * 0.027, height: size * 0.027)
                    .padding(size * 0.012)
            }
            .scaleEffect(y: blinking ? 0.12 : 1)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.maxX * 0.92, y: rect.maxY * 0.72))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.minX * 1.08, y: rect.maxY * 0.72))
            path.closeSubpath()
        }
    }
}

extension Notification.Name {
    static let macPulseShowCleaner = Notification.Name("macpulse.showCleaner")
}
