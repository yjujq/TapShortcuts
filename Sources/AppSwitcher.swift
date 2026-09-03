import AppKit

/// Switching to the previous application without the app switcher.
///
/// Doing it with ⌘⇥ works badly: the system switcher waits for Command to be
/// released and shows its row of icons. Here we simply remember what was
/// frontmost before the current app and activate it — instantly and with no
/// extra visuals.
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
        // Do not record ourselves: opening settings must not push out the
        // application the user will want to come back to.
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
