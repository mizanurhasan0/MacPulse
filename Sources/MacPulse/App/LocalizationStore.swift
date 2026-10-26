import Combine
import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case bangla = "bn"
    case arabic = "ar"

    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .english: "English"
        case .bangla: "বাংলা"
        case .arabic: "العربية"
        }
    }
    var locale: Locale { Locale(identifier: rawValue) }
    var direction: LayoutDirection {
        self == .arabic ? .rightToLeft : .leftToRight
    }
    var layoutDirection: LayoutDirection { direction }
}

@MainActor final class LocalizationStore: ObservableObject {
    @Published private(set) var language: AppLanguage
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: "macpulse.language")
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        defaults.set(language.rawValue, forKey: "macpulse.language")
    }

    func text(_ key: TranslationKey) -> String {
        localized(key, language: language)
    }

    var layoutDirection: LayoutDirection {
        language == .arabic ? .rightToLeft : .leftToRight
    }
}

struct LText: View {
    @EnvironmentObject private var localization: LocalizationStore
    let key: TranslationKey
    var font: Font? = nil
    var color: Color? = nil

    var body: some View {
        Group {
            if let font, let color {
                Text(localization.text(key)).font(font).foregroundStyle(color)
            } else if let font {
                Text(localization.text(key)).font(font)
            } else if let color {
                Text(localization.text(key)).foregroundStyle(color)
            } else {
                Text(localization.text(key))
            }
        }
    }
}
