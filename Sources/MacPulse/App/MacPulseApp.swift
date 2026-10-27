import SwiftUI

@main
struct MacPulseApp: App {
    @StateObject private var model = CleanerModel()
    @StateObject private var localization = LocalizationStore()
    @StateObject private var theme = ThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(localization)
                .environmentObject(theme)
                .environment(\.layoutDirection, localization.layoutDirection)
                .preferredColorScheme(theme.appearance.colorScheme)
                .tint(theme.accent.color)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 1120, height: 760)
    }
}
