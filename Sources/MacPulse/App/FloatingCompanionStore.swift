import AppKit
import Combine
import SwiftUI

@MainActor
final class FloatingCompanionStore: NSObject, ObservableObject {
    @Published private(set) var isEnabled: Bool
    private let defaults: UserDefaults
    private let preferenceKey = "macpulse.floatingCat.enabled"
    private let frameName = "MacPulse.FloatingCat.Frame"
    private var panel: CompanionPanel?
    private var makeContent: (() -> NSView)?
    private var openCleaner: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A new installation starts with the companion disabled.
        isEnabled = defaults.bool(forKey: "macpulse.floatingCat.enabled")
        super.init()
    }

    func configure(
        model: CleanerModel, localization: LocalizationStore, theme: ThemeStore,
        openCleaner: @escaping () -> Void
    ) {
        self.openCleaner = openCleaner
        makeContent = { [weak self] in
            NSHostingView(rootView: QuickCleanerCatWidget(
                onExpand: { [weak self] in
                    self?.openCleaner?()
                    NSApp.activate(ignoringOtherApps: true)
                },
                onResize: { [weak self] in self?.resize(to: $0) })
                .environmentObject(model)
                .environmentObject(localization)
                .environmentObject(theme))
        }
        if isEnabled { showPanel() }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: preferenceKey)
        if enabled {
            showPanel()
        } else {
            panel?.saveFrame(usingName: frameName)
            panel?.close()
            panel = nil
        }
    }

    private func showPanel() {
        guard panel == nil, let makeContent else { return }
        let window = CompanionPanel(
            contentRect: NSRect(x: 0, y: 0, width: 76, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if !window.setFrameUsingName(frameName), let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.maxX - 100,
                y: screen.visibleFrame.minY + 48))
        }
        // Restore position, but always begin with the collapsed character.
        window.setContentSize(NSSize(width: 76, height: 88))
        _ = window.setFrameAutosaveName(frameName)
        panel = window
        window.contentView = makeContent()
        clampToScreen()
        window.orderFrontRegardless()
    }

    private func resize(to size: CGSize) {
        guard let panel else { return }
        let frame = panel.frame
        panel.setFrame(NSRect(
            x: frame.maxX - size.width, y: frame.maxY - size.height,
            width: size.width, height: size.height), display: true)
        clampToScreen()
    }

    private func clampToScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        let frame = panel.frame
        panel.setFrameOrigin(NSPoint(
            x: min(max(frame.minX, bounds.minX), max(bounds.minX, bounds.maxX - frame.width)),
            y: min(max(frame.minY, bounds.minY), max(bounds.minY, bounds.maxY - frame.height))))
    }
}

private final class CompanionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Only Settings controls visibility. In particular, Command-W must not
    // remove the companion when the user closes the Cleaner window.
    override func performClose(_ sender: Any?) {}
}
