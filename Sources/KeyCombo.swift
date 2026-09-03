import AppKit

/// Sending a key combination.
///
/// Unlike running a shortcut, this needs Accessibility access: the system
/// only lets trusted applications post synthetic key events. Without it the
/// call silently does nothing.
enum KeyCombo {
    /// Written as a string such as "cmd+w" or "cmd+shift+t".
    /// Parsed here so the setting stays readable in the plist.
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37,
        "j": 38, "k": 40, "n": 45, "m": 46,
        "tab": 48, "space": 49, "return": 36, "escape": 53, "delete": 51,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    ]

    static func send(_ description: String) {
        let parts = description.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last, let code = keyCodes[last] else {
            NSLog("TapShortcuts: unrecognised combination \"\(description)\"")
            return
        }

        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command":  flags.insert(.maskCommand)
            case "shift":           flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            default: NSLog("TapShortcuts: unknown modifier \"\(part)\"")
            }
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Press and release the modifiers for real rather than only setting
        // a flag on the key itself. It makes no difference for ⌘W, but the app
        // switcher waits precisely for Command to be released; otherwise it
        // stays on screen instead of completing the switch.
        let modifierKeys: [(CGEventFlags, CGKeyCode)] = [
            (.maskCommand, 55), (.maskShift, 56), (.maskAlternate, 58), (.maskControl, 59),
        ]
        let held = modifierKeys.filter { flags.contains($0.0) }

        for (_, key) in held {
            CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?
                .post(tap: .cghidEventTap)
        }
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        for (_, key) in held.reversed() {
            CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?
                .post(tap: .cghidEventTap)
        }
    }

    /// A ready set to choose from in settings. The list is deliberately
    /// short: it covers the everyday cases, while unusual ones are written
    /// straight into the defaults under the bindings.v2 key.
    static let presets: [(title: String, combo: String)] = [
        ("⌘W — close",            "cmd+w"),
        ("⌘⇥ — switch app",       "cmd+tab"),
        ("⌘Q — quit",             "cmd+q"),
        ("⌘T — new tab",          "cmd+t"),
        ("⌘⇧T — reopen tab",      "cmd+shift+t"),
        ("⌃⇥ — next tab",         "ctrl+tab"),
        ("⌃⇧⇥ — previous tab",    "ctrl+shift+tab"),
        ("⌘M — minimise",         "cmd+m"),
        ("⌘H — hide",             "cmd+h"),
        ("F3 — Mission Control",  "f3"),
    ]
}

/// What a gesture does. Stored as a single string to keep the setting
/// simple: "keys:cmd+w" or "shortcut:Wi-Fi On/Off".
enum Action {
    case none
    case keys(String)
    case shortcut(String)
    case previousApp
    case system(SystemAction)
    case app(String)
    /// Shell commands and AppleScript are not offered in settings: they need
    /// a text field and the list is long enough already. They are written by
    /// hand under bindings.v2 as "shell:…" or "script:…".
    case shell(String)
    case script(String)

    static func decode(_ raw: String) -> Action {
        if raw.isEmpty { return .none }
        if raw == "system:previousApp" { return .previousApp }
        if raw.hasPrefix("system:"), let a = SystemAction(rawValue: String(raw.dropFirst(7))) {
            return .system(a)
        }
        if raw.hasPrefix("app:") { return .app(String(raw.dropFirst(4))) }
        if raw.hasPrefix("shell:") { return .shell(String(raw.dropFirst(6))) }
        if raw.hasPrefix("script:") { return .script(String(raw.dropFirst(7))) }
        if raw.hasPrefix("keys:") { return .keys(String(raw.dropFirst(5))) }
        if raw.hasPrefix("shortcut:") { return .shortcut(String(raw.dropFirst(9))) }
        // Entries from the earliest builds stored just the shortcut name.
        return .shortcut(raw)
    }

    func run() {
        switch self {
        case .none: break
        case .keys(let combo): KeyCombo.send(combo)
        case .shortcut(let name): Shortcuts.run(name)
        case .previousApp:
            // An explicit hop to the main thread rather than an assertion
            // about it. Today we only get here from the main thread, but the
            // assertion would quietly turn into a crash if someone called it
            // otherwise — that is exactly how the app crashed during gesture
            // recognition.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { AppSwitcher.shared.switchToPrevious() }
            }
        case .system(let a): a.run()
        case .app(let id): Apps.activate(bundleID: id)
        case .shell(let command): runTool("/bin/sh", ["-c", command])
        case .script(let source): runTool("/usr/bin/osascript", ["-e", source])
        }
    }

    private func runTool(_ tool: String, _ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch {
            NSLog("TapShortcuts: could not run \(tool): \(error)")
        }
    }
}
