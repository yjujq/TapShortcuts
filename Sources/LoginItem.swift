import ServiceManagement

/// Launch at login. SMAppService handles this without a helper tool, but it
/// requires the app to live in the Applications folder.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("TapShortcuts: could not change the login item: \(error)")
        }
    }
}
