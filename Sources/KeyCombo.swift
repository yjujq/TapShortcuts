import AppKit
import Carbon.HIToolbox

/// Sending a key combination.
///
/// Unlike running a shortcut, this needs Accessibility access: the system
/// only lets trusted applications post synthetic key events. Without it the
/// call silently does nothing.
enum KeyCombo {
    /// Keys that produce no character. Their codes are the same on every
    /// layout, so for these alone a table is the right tool.
    private static let namedKeys: [String: Int] = [
        "tab": kVK_Tab, "space": kVK_Space, "return": kVK_Return,
        "escape": kVK_Escape, "delete": kVK_Delete, "forwarddelete": kVK_ForwardDelete,
        "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "down": kVK_DownArrow, "up": kVK_UpArrow,
        "home": kVK_Home, "end": kVK_End,
        "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5,
        "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10,
        "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13, "f14": kVK_F14,
        "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18,
        "f19": kVK_F19, "f20": kVK_F20,
    ]

    /// Character keys, read from a keyboard layout rather than listed by hand.
    ///
    /// They were listed by hand once, and the list had no digits: the two
    /// screenshot actions did nothing at all for as long as it existed, with
    /// the only complaint going to NSLog, which hides the text of a non-system
    /// process. A list is also wrong in principle. An application matches ⌘Q by
    /// the character, not by the key: on AZERTY the Q sits where QWERTY has its
    /// A, and a fixed code would have sent ⌘A.
    ///
    /// Built afresh on every call rather than cached. It is 128 lookups, a
    /// gesture comes a few times a minute at most, and a cache would have to
    /// watch for layout changes to stay right.
    static func characterKeys(in source: TISInputSource,
                              commandHeld: Bool) -> [String: CGKeyCode] {
        var map: [String: CGKeyCode] = [:]
        withLayout(of: source) { layout in
            for code in 0..<128 {
                guard let key = translate(layout, code: code, commandHeld: commandHeld) else { continue }
                // The first code wins. The main row comes before the keypad,
                // so "4" is the key above R and T, not keypad 4.
                if map[key] == nil { map[key] = CGKeyCode(code) }
            }
        }
        return map
    }

    /// The layout asked is the ASCII-capable one: the layout the system itself
    /// falls back to for shortcuts. With a Russian layout active no key types a
    /// "w" at all, and the system reads ⌘Ц as ⌘W through exactly this fallback.
    /// With a Latin layout active, it is simply that layout.
    private static var shortcutLayout: TISInputSource? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
    }

    private static func characterKeys(commandHeld: Bool) -> [String: CGKeyCode] {
        guard let source = shortcutLayout else { return [:] }
        return characterKeys(in: source, commandHeld: commandHeld)
    }

    private static func withLayout(of source: TISInputSource,
                                   _ body: (UnsafePointer<UCKeyboardLayout>) -> Void) {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return
        }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        data.withUnsafeBytes { buffer in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return }
            body(layout)
        }
    }

    /// The character one key types, or nil for a key that types nothing
    /// nameable — a control character or a blank.
    ///
    /// Asked with Command held when the combination holds it: layouts such as
    /// "Dvorak – QWERTY ⌘" switch to QWERTY exactly then.
    private static func translate(_ layout: UnsafePointer<UCKeyboardLayout>,
                                  code: Int, commandHeld: Bool) -> String? {
        let modifiers = commandHeld ? UInt32((cmdKey >> 8) & 0xFF) : 0
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay),
                                    modifiers, UInt32(LMGetKbdType()),
                                    OptionBits(1 << kUCKeyTranslateNoDeadKeysBit),
                                    &deadKeys, chars.count, &length, &chars)
        guard status == noErr, length > 0 else { return nil }
        let key = String(utf16CodeUnits: chars, count: length).lowercased()
        guard !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return key
    }

    /// A key pressed while recording, written back as "cmd+shift+y" — the
    /// same form a ready combination uses, so it is stored and sent the same
    /// way. Nil for a key that has no name, such as keypad Enter.
    ///
    /// Stored by character rather than by key code, and so it follows the
    /// layout: ⌘Q recorded on QWERTY stays ⌘Q after a switch to AZERTY.
    static func describe(code: CGKeyCode, modifiers: NSEvent.ModifierFlags) -> String? {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option)  { parts.append("alt") }
        if modifiers.contains(.shift)   { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }

        var key = namedKeys.first(where: { $0.value == Int(code) })?.key
        if key == nil, let source = shortcutLayout {
            withLayout(of: source) { layout in
                key = translate(layout, code: Int(code), commandHeld: modifiers.contains(.command))
            }
        }
        guard var name = key else { return nil }
        // "+" separates the parts, so the key itself goes by a name.
        if name == "+" { name = "plus" }
        return (parts + [name]).joined(separator: "+")
    }

    /// Modifiers the way the system prints them, in the system's order.
    static func glyphs(for modifiers: NSEvent.ModifierFlags) -> String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option)  { out += "⌥" }
        if modifiers.contains(.shift)   { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out
    }

    /// A combination the way the system prints a shortcut: "⇧⌘Y".
    static func display(_ description: String) -> String {
        let parts = description.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last else { return description }

        var modifiers: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command":       modifiers.insert(.command)
            case "shift":                modifiers.insert(.shift)
            case "ctrl", "control":      modifiers.insert(.control)
            case "alt", "opt", "option": modifiers.insert(.option)
            default: break
            }
        }
        let names: [String: String] = [
            "tab": "⇥", "space": "Space", "return": "↩", "escape": "⎋",
            "delete": "⌫", "forwarddelete": "⌦",
            "left": "←", "right": "→", "down": "↓", "up": "↑",
            "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟", "plus": "+",
        ]
        return glyphs(for: modifiers) + (names[last] ?? last.uppercased())
    }

    /// The key and modifiers for a combination written as "cmd+w", or nil
    /// when any part of it is not recognised — in which case nothing should
    /// be sent, rather than some other combination.
    static func resolve(_ description: String) -> (code: CGKeyCode, flags: CGEventFlags)? {
        let parts = description.lowercased()
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = parts.last else { return nil }

        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command":  flags.insert(.maskCommand)
            case "shift":           flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            default: return nil
            }
        }

        if let named = namedKeys[last] { return (CGKeyCode(named), flags) }
        // "+" separates the parts, so the key itself goes by a name.
        let character = last == "plus" ? "+" : last
        guard let code = characterKeys(commandHeld: flags.contains(.maskCommand))[character] else {
            return nil
        }
        return (code, flags)
    }

    /// Sends a combination written as "cmd+w". Returns false, and sends
    /// nothing, when a part of it is not recognised.
    @discardableResult
    static func send(_ description: String) -> Bool {
        guard let key = resolve(description) else {
            NSLog("TapShortcuts: unrecognised combination \"\(description)\"")
            return false
        }
        post(code: key.code, flags: key.flags)
        return true
    }

    /// Posts a key with its modifiers around it.
    static func post(code: CGKeyCode, flags: CGEventFlags) {
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
    /// short: it covers the everyday cases, and anything else is recorded in
    /// the chooser.
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
