import AppKit

/// Готовые действия над системой.
///
/// Набор отобран по перечню похожих программ, но оставлено только то, что
/// выполнимо открытыми средствами: нажатия клавиш, мультимедийные клавиши,
/// команды системных программ и AppleScript. Всё, что требует частных
/// механизмов — вроде «не беспокоить» — сюда не вошло: такое надёжнее
/// сделать быстрой командой.
enum SystemAction: String, CaseIterable, Identifiable {
    // Рабочие столы и обзор
    case missionControl, appExpose, launchpad, showDesktop
    case spaceLeft, spaceRight
    // Питание и защита
    case lockScreen, sleepDisplay
    // Мультимедиа
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, mute
    // Экран и подсветка
    case brightnessUp, brightnessDown
    // Снимки экрана
    case screenshotScreen, screenshotArea
    // Прочее
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
        // Обзор окон и рабочие столы — обычные сочетания клавиш.
        case .missionControl: KeyCombo.send("ctrl+up")
        case .appExpose:      KeyCombo.send("ctrl+down")
        case .showDesktop:    KeyCombo.send("f11")
        case .spaceLeft:      KeyCombo.send("ctrl+left")
        case .spaceRight:     KeyCombo.send("ctrl+right")
        case .lockScreen:     KeyCombo.send("ctrl+cmd+q")
        case .screenshotScreen: KeyCombo.send("cmd+shift+3")
        case .screenshotArea:   KeyCombo.send("cmd+shift+4")

        case .launchpad:   open(app: "/System/Applications/Launchpad.app")

        // Гашение экрана делает системная программа: своего пути к этому нет.
        case .sleepDisplay: shell("/usr/bin/pmset", ["displaysleepnow"])

        // Мультимедийные клавиши идут не как обычные нажатия, а особым
        // событием — обычная клавиатура их так и посылает.
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

    // MARK: - Способы выполнения

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

    /// AppleScript выполняем отдельной программой, а не через NSAppleScript:
    /// так вызов не подвешивает наш поток, если сценарий задумается.
    private func script(_ source: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// Мультимедийная клавиша. Такие события система принимает только
    /// в особом виде, с подтипом 8 и упакованными в поле данных
    /// кодом клавиши и состоянием.
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
