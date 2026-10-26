import SwiftUI

@main
struct MacPulseApp: App {
    @StateObject private var model = DashboardModel()
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
                .frame(minWidth: 680, minHeight: 500)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(localization.text(.settings)) { model.selectedSection = "Settings" }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
