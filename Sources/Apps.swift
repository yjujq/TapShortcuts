import AppKit

/// Список установленных приложений — для действия «открыть приложение».
enum Apps {
    /// Читается при открытии настроек: обход папок недешёвый, а состав
    /// меняется редко.
    static func list() -> [(name: String, bundleID: String)] {
        let folders = ["/Applications", "/System/Applications",
                       NSHomeDirectory() + "/Applications"]
        var found: [String: String] = [:]      // имя -> опознаватель

        for folder in folders {
            let url = URL(fileURLWithPath: folder)
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "app" {
                guard let bundle = Bundle(url: item),
                      let id = bundle.bundleIdentifier else { continue }
                let name = item.deletingPathExtension().lastPathComponent
                found[name] = id
            }
            // Служебные программы лежат отдельной вложенной папкой.
            let utilities = url.appendingPathComponent("Utilities")
            if let items = try? FileManager.default.contentsOfDirectory(
                at: utilities, includingPropertiesForKeys: nil) {
                for item in items where item.pathExtension == "app" {
                    guard let bundle = Bundle(url: item),
                          let id = bundle.bundleIdentifier else { continue }
                    found[item.deletingPathExtension().lastPathComponent] = id
                }
            }
        }

        return found
            .map { (name: $0.key, bundleID: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Открыть или вывести вперёд, если уже запущено.
    static func activate(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            if #available(macOS 14.0, *) { app.activate() }
            else { app.activate(options: [.activateIgnoringOtherApps]) }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("TapShortcuts: приложение \(bundleID) не найдено")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
