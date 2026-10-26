import SwiftUI

private struct WorkspaceWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 900
}

extension EnvironmentValues {
    var workspaceWidth: CGFloat {
        get { self[WorkspaceWidthKey.self] }
        set { self[WorkspaceWidthKey.self] = newValue }
    }
}

enum WorkspaceMetrics {
    static func inset(for width: CGFloat) -> CGFloat {
        width < 560 ? 16 : (width < 900 ? 24 : 32)
    }
}

/// The viewport fills the detail pane. Only the document inside it has a reading-width limit.
/// Keeping the width limit inside the scroll view keeps its scroller at the window edge.
struct PageScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    content
                }
                .frame(maxWidth: 1160, alignment: .leading)
                .padding(.horizontal, WorkspaceMetrics.inset(for: geometry.size.width))
                .padding(.vertical, geometry.size.width < 560 ? 20 : 28)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .environment(\.workspaceWidth, geometry.size.width)
            .background(WorkspaceBackground())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkspaceBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [theme.accent.color.opacity(colorScheme == .dark ? 0.07 : 0.035), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(height: 340)
            }
            .ignoresSafeArea()
    }
}

struct AdaptiveStack<Content: View>: View {
    @Environment(\.workspaceWidth) private var width
    var breakpoint: CGFloat = 700
    var spacing: CGFloat = 18
    var alignment: VerticalAlignment = .center
    @ViewBuilder let content: Content

    var body: some View {
        let layout =
            width < breakpoint
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.07)))
            .shadow(color: .black.opacity(0.025), radius: 10, x: 0, y: 3)
    }
}

struct IconTile: View {
    let symbol: String
    var size: CGFloat = 42

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.09), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct PageHeader: View {
    @EnvironmentObject private var localization: LocalizationStore
    @Environment(\.workspaceWidth) private var width
    let title: TranslationKey
    let subtitle: TranslationKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.text(title))
                .font(.system(size: width < 560 ? 25 : 30, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(localization.text(subtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor func pageHeader(_ title: TranslationKey, subtitle: TranslationKey) -> some View {
    PageHeader(title: title, subtitle: subtitle)
}

struct InfoNote: View {
    let text: String
    var symbol = "info.circle"

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsCard<Content: View>: View {
    @EnvironmentObject private var localization: LocalizationStore
    let title: TranslationKey
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 18) {
                Label(localization.text(title), systemImage: symbol)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                content
            }
        }
    }
}
