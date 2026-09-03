import ServiceManagement

/// Автозапуск. SMAppService умеет это без вспомогательной программы,
/// но требует, чтобы приложение лежало в папке «Программы».
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
            NSLog("TapShortcuts: не удалось изменить автозапуск: \(error)")
        }
    }
}
