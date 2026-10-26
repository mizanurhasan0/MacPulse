import AppKit
import Combine
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var translationKey: TranslationKey {
        switch self {
        case .system: .systemTheme
        case .light: .lightTheme
        case .dark: .darkTheme
        }
    }
}

enum AccentPalette: String, CaseIterable, Identifiable {
    case ocean
    case violet
    case emerald
    case rose

    var id: String { rawValue }
    var color: Color {
        switch self {
        case .ocean: Self.adaptive(light: (0.08, 0.43, 0.55), dark: (0.29, 0.72, 0.82))
        case .violet: Self.adaptive(light: (0.39, 0.31, 0.75), dark: (0.67, 0.57, 0.98))
        case .emerald: Self.adaptive(light: (0.12, 0.48, 0.35), dark: (0.35, 0.79, 0.61))
        case .rose: Self.adaptive(light: (0.70, 0.27, 0.39), dark: (0.98, 0.53, 0.64))
        }
    }

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: value.0, green: value.1, blue: value.2, alpha: 1)
            })
    }

    var translationKey: TranslationKey {
        switch self {
        case .ocean: .themeOcean
        case .violet: .themeViolet
        case .emerald: .themeEmerald
        case .rose: .themeRose
        }
    }
}

@MainActor final class ThemeStore: ObservableObject {
    @Published private(set) var appearance: AppearanceMode
    @Published private(set) var accent: AccentPalette
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance =
            defaults.string(forKey: "macpulse.appearance")
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        accent =
            defaults.string(forKey: "macpulse.accent")
            .flatMap(AccentPalette.init(rawValue:)) ?? .ocean
    }

    func setAppearance(_ value: AppearanceMode) {
        guard appearance != value else { return }
        appearance = value
        defaults.set(value.rawValue, forKey: "macpulse.appearance")
    }

    func setAccent(_ value: AccentPalette) {
        guard accent != value else { return }
        accent = value
        defaults.set(value.rawValue, forKey: "macpulse.accent")
    }
}
