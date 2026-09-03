import AppKit
import SwiftUI
import Combine

/// TapShortcuts — постукивание несколькими пальцами по трекпаду
/// запускает быструю команду. Живёт в строке меню, без окна и без дока.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store.shared
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var iconWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyIconVisibility()
        // Значок можно убрать из строки меню, поэтому следим за настройкой.
        iconWatch = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.applyIconVisibility() }
            }
        }

        TouchWatcher.shared.onGesture = { [weak self] gesture in
            MainActor.assumeIsolated { self?.handle(gesture) }
        }
        // Двойное постукивание требует придержать одиночное — сообщаем
        // распознавателю, назначено ли оно, чтобы не задерживать зря.
        TouchWatcher.shared.isBound = { [weak self] gesture in
            MainActor.assumeIsolated {
                guard let self else { return false }
                if case .none = self.store.action(for: gesture) { return false }
                return true
            }
        }
        TouchWatcher.shared.start()
        AppSwitcher.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TouchWatcher.shared.stop()
    }

    /// Повторный запуск из Finder открывает настройки — иначе к ним
    /// не вернуться, если значок в строке меню не замечен.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        togglePopover()
        return true
    }

    private func handle(_ gesture: Gesture) {
        guard store.enabled else { return }
        let action = store.action(for: gesture)
        if case .none = action { return }
        action.run()
        flash()
    }

    /// Короткая отметка в строке меню: без неё непонятно, засчитан ли жест,
    /// особенно когда сама команда ничего видимого не делает.
    private func flash() {
        guard let button = statusItem?.button else { return }
        button.appearsDisabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            button.appearsDisabled = false
        }
    }

    /// Значок появляется и снимается по настройке. Когда его нет, вернуться
    /// к настройкам можно повторным запуском из Finder — это обрабатывается
    /// в applicationShouldHandleReopen.
    private func applyIconVisibility() {
        if store.showStatusIcon {
            if statusItem == nil { setUpStatusItem() }
        } else if let item = statusItem {
            if popover.isShown { popover.performClose(nil) }
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

        popover.contentViewController = NSHostingController(rootView: SettingsView(store: .shared))
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 520)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else {
            // Значка нет — показываем настройки отдельным окном, иначе
            // к ним было бы не подступиться вовсе.
            SettingsWindow.show()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

let app = NSApplication.shared

// Делегат обязан жить в глобальной переменной: NSApplication держит его
// слабой ссылкой, и внутри замыкания он был бы сразу освобождён.
let delegate: AppDelegate = MainActor.assumeIsolated { AppDelegate() }

MainActor.assumeIsolated {
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // без иконки в доке
    app.run()
}
