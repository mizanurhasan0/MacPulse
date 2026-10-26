import SwiftUI

enum StorageTab: Int, CaseIterable, Identifiable {
    case caches, large, duplicates
    var id: Int { rawValue }
    var title: WorkflowKey {
        switch self { case .caches: .cacheTab; case .large: .largeTab; case .duplicates: .duplicatesTab }
    }
    var summary: WorkflowKey {
        switch self { case .caches: .storageCacheSummary; case .large: .storageLargeSummary; case .duplicates: .storageDuplicateSummary }
    }
    var symbol: String {
        switch self { case .caches: "folder.badge.gearshape"; case .large: "doc.text.magnifyingglass"; case .duplicates: "doc.on.doc" }
    }
}

struct StorageCapacityCard: View {
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.workspaceWidth) private var width
    @Environment(\.colorScheme) private var colorScheme
    let storage: StorageReading
    let openTrash: () -> Void

    private var usageColor: Color { storage.usedFraction >= 0.9 ? .orange : theme.accent.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(theme.accent.color)
                        .frame(width: 46, height: 46)
                        .background(theme.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localization.text(.volumeCapacity)).font(.callout).foregroundStyle(.secondary)
                        Text(formatBytes(storage.availableBytes))
                            .font(.system(size: width < 560 ? 26 : 32, weight: .semibold, design: .rounded))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                        Text(localization.workflow(.storageAvailableSpace)).font(.caption).foregroundStyle(.secondary)
                    }
                    .layoutPriority(1)
                }
                Spacer(minLength: 0)
                Button(action: openTrash) {
                    Label(localization.workflow(.openTrash), systemImage: "trash")
                }
                .buttonStyle(.bordered).controlSize(.large)
                .help(localization.workflow(.openTrash))
                .accessibilityIdentifier("storage.open-trash")
            }
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geometry in
                    Capsule().fill(Color.primary.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Capsule().fill(usageColor.gradient)
                                .frame(width: geometry.size.width * min(1, max(0, storage.usedFraction)))
                        }
                }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localization.text(.storageCapacity))
                .accessibilityValue(localization.workflow(.storageUsedPercent, Int(storage.usedFraction * 100)))
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label {
                        Text(localization.workflow(.storageUsedOfTotal, formatBytes(storage.usedBytes), formatBytes(storage.totalBytes)))
                    } icon: { Circle().fill(usageColor).frame(width: 7, height: 7) }
                    Spacer(minLength: 0)
                    Text(localization.workflow(.storageUsedPercent, Int(storage.usedFraction * 100)))
                        .monospacedDigit().fixedSize()
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(width < 560 ? 18 : 24)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(LinearGradient(colors: [theme.accent.color.opacity(colorScheme == .dark ? 0.10 : 0.05), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.07)))
    }
}

struct StorageCategoryPicker: View {
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.workspaceWidth) private var width
    @Binding var selection: Int

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(StorageTab.allCases) { tab in
                StorageCategoryButton(tab: tab, selected: selection == tab.rawValue, compact: width < 760) {
                    selection = tab.rawValue
                }
                .frame(maxWidth: .infinity)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(localization.workflow(.storageCategories))
    }
}

private struct StorageCategoryButton: View {
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    let tab: StorageTab
    let selected: Bool
    let compact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 9 : 12) {
                HStack {
                    Image(systemName: tab.symbol).font(.system(size: 19, weight: .medium))
                        .foregroundStyle(selected ? theme.accent.color : .secondary)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? theme.accent.color : Color.primary.opacity(0.18))
                }
                .frame(height: 24)
                VStack(alignment: .leading, spacing: 5) {
                    Text(localization.workflow(tab.title)).font(.callout.weight(.semibold))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: compact ? 32 : 18, alignment: .topLeading)
                    if !compact {
                        Text(localization.workflow(tab.summary)).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 28, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 64 : 76, maxHeight: .infinity, alignment: .topLeading)
            .padding(compact ? 13 : 16)
            .background(selected ? theme.accent.color.opacity(0.09) : Color.primary.opacity(hovered ? 0.045 : 0.018),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? theme.accent.color.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: selected ? 1.3 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help(localization.workflow(tab.summary))
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selected)
        .accessibilityLabel(localization.workflow(tab.title))
        .accessibilityHint(localization.workflow(tab.summary))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("storage.category.\(tab.rawValue)")
    }
}

/// Dark palettes use a lighter accent, so primary labels need dark ink rather
/// than white text. Disabled controls retain a distinct, neutral appearance.
struct StoragePrimaryButtonStyle: ButtonStyle {
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(enabled ? (colorScheme == .dark ? Color.black.opacity(0.88) : .white) : .secondary)
            .padding(.horizontal, 15)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .background(enabled ? theme.accent.color.opacity(configuration.isPressed ? 0.8 : 1) : Color.primary.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct StorageEmptyState: View {
    @EnvironmentObject private var theme: ThemeStore
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 25, weight: .light))
                .foregroundStyle(theme.accent.color)
                .frame(width: 56, height: 62)
                .background(theme.accent.color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
    }
}

struct StorageScanHeading: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            IconTile(symbol: symbol, size: 42)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
