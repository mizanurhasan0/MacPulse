enum TranslationKey {
    case systemTheme, lightTheme, darkTheme
    case themeOcean, themeViolet, themeEmerald, themeRose
}

func localized(_ key: TranslationKey, language: AppLanguage) -> String {
    switch (key, language) {
    case (.systemTheme, .bangla): "সিস্টেম"
    case (.lightTheme, .bangla): "লাইট"
    case (.darkTheme, .bangla): "ডার্ক"
    case (.themeOcean, .bangla): "ওশান"
    case (.themeViolet, .bangla): "ভায়োলেট"
    case (.themeEmerald, .bangla): "এমেরাল্ড"
    case (.themeRose, .bangla): "রোজ"
    case (.systemTheme, _): "System"
    case (.lightTheme, _): "Light"
    case (.darkTheme, _): "Dark"
    case (.themeOcean, _): "Ocean"
    case (.themeViolet, _): "Violet"
    case (.themeEmerald, _): "Emerald"
    case (.themeRose, _): "Rose"
    }
}
