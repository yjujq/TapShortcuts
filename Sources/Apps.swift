import AppKit

/// The list of installed applications, for the "open application" action.
enum Apps {
    /// Read when settings open: walking the folders is not cheap and the
    /// set of applications rarely changes.
    static func list() -> [(name: String, bundleID: String)] {
        let folders = ["/Applications", "/System/Applications",
                       NSHomeDirectory() + "/Applications"]
        var found: [String: String] = [:]      // name -> bundle identifier

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
            // Utilities live in their own nested folder.
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

    /// Open it, or bring it to the front if it is already running.
    static func activate(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        if let app = running.first {
            if #available(macOS 14.0, *) { app.activate() }
            else { app.activate(options: [.activateIgnoringOtherApps]) }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("TapShortcuts: application \(bundleID) not found")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
