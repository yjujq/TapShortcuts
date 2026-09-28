import AppKit
import SwiftUI
import Combine

/// TapShortcuts — a multi-finger tap on the trackpad runs an action.
/// Lives in the menu bar, with no window and no Dock icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store.shared
    private var statusItem: NSStatusItem!
    private let settingsPanel = FloatingPanel()
    private var iconWatch: AnyCancellable?
    private var bindingsWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyIconVisibility()
        // The icon can be removed from the menu bar, so watch the setting.
        iconWatch = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applyIconVisibility() }
            }
        }

        TouchWatcher.shared.onGesture = { [weak self] gesture in
            MainActor.assumeIsolated { self?.handle(gesture) }
        }
        // A double tap requires holding back the single one, so tell the
        // recogniser which gestures are bound and avoid delaying for nothing.
        // We hand over a ready set rather than a way to ask: recognition runs
        // on the trackpad thread, and settings must not be touched from there.
        updateBoundGestures()
        TouchWatcher.shared.setGuardsEnabled(store.falseGuards)
        bindingsWatch = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.updateBoundGestures()
                    if let on = self?.store.falseGuards {
                        TouchWatcher.shared.setGuardsEnabled(on)
                    }
                }
            }
        }
        TouchWatcher.shared.start()
        AppSwitcher.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchWatcher.shared.stop()
    }

    /// Relaunching from Finder opens settings — otherwise there is no way
    /// back to them if the menu bar icon went unnoticed.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        togglePopover()
        return true
    }

    private func updateBoundGestures() {
        let taken = store.bindings
            .filter { !$0.value.isEmpty }
            .keys
        TouchWatcher.shared.setBound(Set(taken))
    }

    private func handle(_ gesture: Gesture) {
        guard store.enabled, !store.frontmostIsExcluded else { return }
        let action = store.action(for: gesture)
        if case .none = action { return }
        // Felt before the action runs, so the answer comes the moment the
        // gesture is recognised rather than after whatever the action does.
        Haptics.play(store.haptic(for: gesture))
        action.run()
        flash()
    }

    /// A brief flash in the menu bar: without it there is no telling whether
    /// the gesture registered, especially when the action does nothing visible.
    private func flash() {
        guard let button = statusItem?.button else { return }
        button.appearsDisabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            button.appearsDisabled = false
        }
    }

    /// The icon appears and disappears with the setting. When it is gone,
    /// settings are reachable by relaunching from Finder — handled in
    /// applicationShouldHandleReopen.
    private func applyIconVisibility() {
        if store.showStatusIcon {
            if statusItem == nil { setUpStatusItem() }
        } else if let item = statusItem {
            settingsPanel.hide()
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap",
                                           accessibilityDescription: "TapShortcuts")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else {
            // No icon, so show settings in a window of their own; otherwise
            // there would be no way to reach them at all.
            SettingsWindow.show()
            return
        }
        if settingsPanel.isShown {
            settingsPanel.hide()
        } else {
            // takesFocus: settings hold text fields and pickers, which take no
            // input at all in a panel that never becomes key.
            settingsPanel.show(SettingsView(store: .shared).panelChrome(),
                               below: button, takesFocus: true)
        }
    }
}

let app = NSApplication.shared

// The delegate must live in a global: NSApplication holds it weakly, and
// inside a closure it would be released immediately.
let delegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // no Dock icon
    app.run()
}
