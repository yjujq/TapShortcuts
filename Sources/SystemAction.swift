import AppKit
import Carbon.HIToolbox

/// Ready-made actions on the system.
///
/// The set was chosen from what comparable tools offer, keeping only what is
/// achievable with public means: key presses, media keys, system command-line
/// tools and AppleScript. Anything needing private frameworks — Do Not Disturb,
/// for one — was left out: such things are more reliable as a Shortcut.
enum SystemAction: String, CaseIterable, Identifiable {
    // Spaces and overview
    case missionControl, appExpose, launchpad, showDesktop
    case spaceLeft, spaceRight
    // Power and security
    case lockScreen, sleepDisplay
    // Media
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, mute
    // Display and backlight
    case brightnessUp, brightnessDown
    // Screenshots
    case screenshotScreen, screenshotArea
    // Other
    case toggleDarkMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .launchpad: return "Launchpad"
        case .showDesktop: return "Show desktop"
        case .spaceLeft: return "Space to the left"
        case .spaceRight: return "Space to the right"
        case .lockScreen: return "Lock screen"
        case .sleepDisplay: return "Sleep display"
        case .playPause: return "Play / pause"
        case .nextTrack: return "Next track"
        case .previousTrack: return "Previous track"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .brightnessUp: return "Brightness up"
        case .brightnessDown: return "Brightness down"
        case .screenshotScreen: return "Screenshot: whole screen"
        case .screenshotArea: return "Screenshot: selected area"
        case .toggleDarkMode: return "Toggle dark mode"
        }
    }

    /// The system shortcut behind this action, where there is one.
    var hotKey: SystemHotKey? {
        switch self {
        case .missionControl:   return .missionControl
        case .appExpose:        return .appWindows
        case .showDesktop:      return .showDesktop
        case .spaceLeft:        return .spaceLeft
        case .spaceRight:       return .spaceRight
        case .screenshotScreen: return .screenshotScreen
        case .screenshotArea:   return .screenshotArea
        default:                return nil
        }
    }

    func run() {
        switch self {
        // Window overview and spaces are plain key combinations.
        case .missionControl, .appExpose, .showDesktop, .spaceLeft, .spaceRight,
             .screenshotScreen, .screenshotArea:
            hotKey?.send()
        // Not a system shortcut but the Apple menu's own key equivalent, which
        // is matched by character like any application's.
        case .lockScreen:     KeyCombo.send("ctrl+cmd+q")

        case .launchpad:   open(app: "/System/Applications/Launchpad.app")

        // Sleeping the display is done by a system tool: there is no own way to it.
        case .sleepDisplay: shell("/usr/bin/pmset", ["displaysleepnow"])

        // Media keys travel not as ordinary key presses but as a special
        // event — that is how a real keyboard sends them.
        case .playPause:     media(16)
        case .nextTrack:     media(17)
        case .previousTrack: media(18)
        case .volumeUp:      media(0)
        case .volumeDown:    media(1)
        case .mute:          media(7)
        case .brightnessUp:   media(2)
        case .brightnessDown: media(3)

        case .toggleDarkMode:
            script("""
            tell application "System Events" to tell appearance preferences
                set dark mode to not dark mode
            end tell
            """)
        }
    }

    // MARK: - Ways of running things

    private func open(app path: String) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func shell(_ tool: String, _ arguments: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// AppleScript runs through a separate tool rather than NSAppleScript:
    /// that way a script that stalls does not block our thread.
    private func script(_ source: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// A media key. The system accepts such events only in a special shape,
    /// with subtype 8 and the key code and state packed into the data field.
    private func media(_ key: Int32) {
        for down in [true, false] {
            let flags: NSEvent.ModifierFlags = down ? NSEvent.ModifierFlags(rawValue: 0xA00)
                                                    : NSEvent.ModifierFlags(rawValue: 0xB00)
            let data = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil,
                subtype: 8, data1: data, data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

/// A shortcut the system itself answers to, sent the way the user has it set.
///
/// The system matches these by key code rather than by character, so they are
/// sent by key code. Looked up by character they would break on AZERTY: the
/// row above the letters types "&é\"'" there unshifted, a "4" would be found
/// on the keypad instead, and the screenshot shortcut does not answer to it.
///
/// The code and modifiers come from the user's own configuration in
/// com.apple.symbolichotkeys, falling back to the system default where nothing
/// is stored. A shortcut moved in System Settings is followed; one switched off
/// there is known to be off, instead of being sent into the void.
struct SystemHotKey {
    let id: Int
    let defaultCode: Int
    let defaultFlags: CGEventFlags

    /// The key and modifiers to send, or nil when the user has switched the
    /// shortcut off.
    var current: (code: CGKeyCode, flags: CGEventFlags)? {
        let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
        guard let entry = all?[String(id)] as? [String: Any] else {
            return (CGKeyCode(defaultCode), defaultFlags)
        }
        if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
        // Enabled with no value stored means the default — which is how the
        // spaces shortcuts, 79 and 81, were found stored on this machine.
        guard let value = entry["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int], parameters.count >= 3 else {
            return (CGKeyCode(defaultCode), defaultFlags)
        }
        // Stored as (character, key code, modifier mask); the mask uses the
        // same bits as CGEventFlags.
        return (CGKeyCode(parameters[1]), CGEventFlags(rawValue: UInt64(parameters[2])))
    }

    var isOn: Bool { current != nil }

    @discardableResult
    func send() -> Bool {
        guard let key = current else { return false }
        KeyCombo.post(code: key.code, flags: key.flags)
        return true
    }

    // The defaults are the values the system stores for these shortcuts,
    // read from com.apple.symbolichotkeys rather than recalled — Mission
    // Control, for one, carries Control alone and no function-key flag.
    static let screenshotScreen = SystemHotKey(id: 28, defaultCode: kVK_ANSI_3,
                                               defaultFlags: [.maskShift, .maskCommand])
    static let screenshotArea   = SystemHotKey(id: 30, defaultCode: kVK_ANSI_4,
                                               defaultFlags: [.maskShift, .maskCommand])
    static let missionControl   = SystemHotKey(id: 32, defaultCode: kVK_UpArrow,
                                               defaultFlags: .maskControl)
    static let appWindows       = SystemHotKey(id: 33, defaultCode: kVK_DownArrow,
                                               defaultFlags: .maskControl)
    static let showDesktop      = SystemHotKey(id: 36, defaultCode: kVK_F11,
                                               defaultFlags: [])
    static let spaceLeft        = SystemHotKey(id: 79, defaultCode: kVK_LeftArrow,
                                               defaultFlags: .maskControl)
    static let spaceRight       = SystemHotKey(id: 81, defaultCode: kVK_RightArrow,
                                               defaultFlags: .maskControl)
}
