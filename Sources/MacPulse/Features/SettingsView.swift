import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: DashboardModel
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var theme: ThemeStore
    @AppStorage("monitoringEnabled") private var monitoringEnabled = true
    @AppStorage("monitoringInterval") private var monitoringInterval = 3.0

    var body: some View {
        PageScrollView {
            pageHeader(.settings, subtitle: .settingsIntro)
            appearanceCard
            SurfaceCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label(localization.workflow(.scanPerformance), systemImage: "externaldrive.badge.magnifyingglass")
                        .font(.headline)
                    Toggle(localization.workflow(.reuseFingerprints), isOn: Binding(
                        get: { model.reuseScanFingerprints },
                        set: { enabled in Task { await model.setReuseScanFingerprints(enabled) } }))
                        .toggleStyle(.switch)
                        .disabled(model.isBusy)
                    InfoNote(text: localization.workflow(.reuseFingerprintsDetails))
                    Button(localization.workflow(.clearScanMemory)) {
                        Task { await model.clearScanMemory() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isBusy)
                    if model.workflowNotice == .scanMemoryCleared {
                        Text(localization.workflow(.scanMemoryCleared)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            SettingsCard(title: .settingsPerformance, symbol: "waveform.path.ecg") {
                Toggle(localization.text(.monitorWhileOpen), isOn: $monitoringEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: monitoringEnabled) { _, enabled in
                        model.updateMonitoringSettings(enabled: enabled, interval: monitoringInterval)
                    }
                Divider()
                Button(localization.workflow(.restoreRecommendations)) { model.resetSnoozedFindings() }
                    .buttonStyle(.bordered)
                VStack(alignment: .leading, spacing: 10) {
                    LText(key: .refreshInterval, font: .subheadline.weight(.medium))
                    Picker(localization.text(.refreshInterval), selection: $monitoringInterval) {
                        ForEach([2.0, 3.0, 5.0], id: \.self) { interval in
                            Text("\(Int(interval)) \(localization.text(.seconds))").tag(interval)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(!monitoringEnabled)
                    .onChange(of: monitoringInterval) { _, interval in
                        model.updateMonitoringSettings(enabled: monitoringEnabled, interval: interval)
                    }
                }
            }
            SettingsCard(title: .language, symbol: "globe") {
                Picker(
                    localization.text(.language),
                    selection: Binding(
                        get: { localization.language }, set: { localization.setLanguage($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                InfoNote(text: localization.text(.languageRestartNote))
            }
            SettingsCard(title: .privacy, symbol: "lock.shield") {
                LText(key: .localOnly, font: .subheadline.weight(.medium))
                LText(key: .privacyDetails, color: .secondary)
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
            }
            SettingsCard(title: .about, symbol: "info.circle") {
                LabeledContent(
                    localization.text(.version),
                    value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                Divider()
                LabeledContent(
                    localization.text(.macOSVersion), value: ProcessInfo.processInfo.operatingSystemVersionString)
                InfoNote(text: localization.text(.settingsLimitations))
            }
        }
        .navigationTitle(localization.text(.settings))
    }

    private var appearanceCard: some View {
        SettingsCard(title: .appearance, symbol: "paintpalette") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                ForEach(AppearanceMode.allCases) { mode in
                    AppearanceOption(mode: mode, selected: theme.appearance == mode) { theme.setAppearance(mode) }
                }
            }
            Divider()
            LText(key: .accentColor, font: .subheadline.weight(.medium))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
                ForEach(AccentPalette.allCases) { palette in
                    AccentOption(palette: palette, selected: theme.accent == palette) { theme.setAccent(palette) }
                }
            }
            InfoNote(text: localization.text(.themeChangeNote))
        }
    }
}

private struct AppearanceOption: View {
    @EnvironmentObject private var localization: LocalizationStore
    @EnvironmentObject private var theme: ThemeStore
    let mode: AppearanceMode
    let selected: Bool
    let action: () -> Void

    private var previewBackground: Color {
        mode == .dark ? Color(white: 0.15) : Color(white: 0.96)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(mode == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(theme.accent.color).frame(height: 7)
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 4).fill(theme.accent.color.opacity(0.16))
                            RoundedRectangle(cornerRadius: 4).fill(theme.accent.color.opacity(0.10))
                        }
                    }
                }
                .padding(10)
                .frame(height: 64)
                .background(previewBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if mode == .system {
                        Image(systemName: "circle.lefthalf.filled").font(.title3)
                            .foregroundStyle(.gray)
                    }
                }
                HStack(spacing: 4) {
                    Text(localization.text(mode.translationKey)).font(.callout.weight(.medium))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(
                selected ? theme.accent.color.opacity(0.06) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        selected ? theme.accent.color : Color.primary.opacity(0.07), lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localization.text(mode.translationKey))
        .accessibilityValue(selected ? localization.text(.selectedOption) : "")
    }
}

private struct AccentOption: View {
    @EnvironmentObject private var localization: LocalizationStore
    let palette: AccentPalette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(palette.color).frame(width: 22, height: 22)
                    .overlay {
                        if selected { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) }
                    }
                Text(localization.text(palette.translationKey)).font(.callout.weight(.medium))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(palette.color.opacity(selected ? 0.08 : 0.025), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? palette.color : Color.primary.opacity(0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localization.text(palette.translationKey))
        .accessibilityValue(selected ? localization.text(.selectedOption) : "")
    }
}
