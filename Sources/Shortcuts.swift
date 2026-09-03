import Foundation

/// Running Shortcuts through the system's own `shortcuts` tool.
///
/// The `shortcuts://run-shortcut` URL scheme exists too, but it brings the
/// Shortcuts app itself to the front. Going through the tool runs the shortcut
/// quietly, which is what a gesture needs.
enum Shortcuts {
    private static let binary = "/usr/bin/shortcuts"

    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: binary)
    }

    /// The list of installed shortcuts. Read when settings open rather than
    /// continuously: the call is not cheap.
    static func list() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        } catch {
            NSLog("TapShortcuts: could not read the list of shortcuts: \(error)")
            return []
        }
    }

    /// Run one by name. We do not wait for it to finish: a shortcut can run
    /// for a long time, and a gesture must let go of us at once.
    static func run(_ name: String) {
        guard !name.isEmpty else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = ["run", name]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch {
            NSLog("TapShortcuts: shortcut \"\(name)\" failed to start: \(error)")
        }
    }
}
