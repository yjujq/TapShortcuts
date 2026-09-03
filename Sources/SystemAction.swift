import AppKit

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

    func run() {
        switch self {
        // Window overview and spaces are plain key combinations.
        case .missionControl: KeyCombo.send("ctrl+up")
        case .appExpose:      KeyCombo.send("ctrl+down")
        case .showDesktop:    KeyCombo.send("f11")
        case .spaceLeft:      KeyCombo.send("ctrl+left")
        case .spaceRight:     KeyCombo.send("ctrl+right")
        case .lockScreen:     KeyCombo.send("ctrl+cmd+q")
        case .screenshotScreen: KeyCombo.send("cmd+shift+3")
        case .screenshotArea:   KeyCombo.send("cmd+shift+4")

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
            script("tell application \"Finder\" to empty trash")
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
