import AppKit

/// Переход к предыдущему приложению без переключателя.
///
/// Через ⌘⇥ это делается плохо: системный переключатель ждёт отпускания
/// Command и показывает свою полосу значков. Здесь мы просто помним, что было
/// впереди до нынешнего, и активируем его — мгновенно и без лишней картинки.
@MainActor
final class AppSwitcher {
    static let shared = AppSwitcher()

    private var current: NSRunningApplication?
    private var previous: NSRunningApplication?

    private init() {}

    func start() {
        current = NSWorkspace.shared.frontmostApplication
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            MainActor.assumeIsolated {
                let key = NSWorkspace.applicationUserInfoKey
                guard let app = note.userInfo?[key] as? NSRunningApplication else { return }
                AppSwitcher.shared.record(app)
            }
        }
    }

    private func record(_ app: NSRunningApplication) {
        // Себя в историю не пишем: открытие настроек не должно вытеснять
        // из неё то приложение, к которому потом захотят вернуться.
        guard app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
        guard app != current else { return }
        previous = current
        current = app
    }

    func switchToPrevious() {
        guard let previous, !previous.isTerminated else { return }
        if #available(macOS 14.0, *) {
            previous.activate()
        } else {
            previous.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
