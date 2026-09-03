import AppKit

/// Отправка сочетания клавиш.
///
/// В отличие от запуска быстрой команды это требует доступа к Универсальному
/// управлению: синтетические нажатия система пропускает только доверенным
/// приложениям. Без доступа вызов молча ничего не сделает.
enum KeyCombo {
    /// Записывается строкой вида «cmd+w» или «cmd+shift+t».
    /// Разбор здесь же, чтобы настройка оставалась читаемой в plist.
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
            NSLog("TapShortcuts: непонятное сочетание «\(description)»")
            return
        }

        var flags: CGEventFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command":  flags.insert(.maskCommand)
            case "shift":           flags.insert(.maskShift)
            case "ctrl", "control": flags.insert(.maskControl)
            case "alt", "opt", "option": flags.insert(.maskAlternate)
            default: NSLog("TapShortcuts: неизвестный модификатор «\(part)»")
            }
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Модификаторы нажимаем и отпускаем по-настоящему, а не только
        // выставляем флаг на самой клавише. Для ⌘W разницы нет, но
        // переключатель приложений ждёт именно отпускания Command, иначе
        // остаётся висеть на экране вместо того, чтобы совершить переход.
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

    /// Готовый набор для выбора в настройках. Список короткий намеренно:
    /// он покрывает обиходное, а необычное вписывается прямо в настройках
    /// системы через ключ bindings.v2.
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

/// Что жест делает. Хранится одной строкой, чтобы настройка оставалась
/// простой: «keys:cmd+w» или «shortcut:Wi-Fi On/Off».
enum Action {
    case none
    case keys(String)
    case shortcut(String)
    case previousApp
    case system(SystemAction)
    case app(String)
    /// Команда оболочки и сценарий AppleScript в настройках не выбираются:
    /// для них нужно поле ввода, а список и так длинный. Вписываются вручную
    /// ключом bindings.v2 — «shell:…» или «script:…».
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
        // Записи первых сборок хранили просто имя команды.
        return .shortcut(raw)
    }

    func run() {
        switch self {
        case .none: break
        case .keys(let combo): KeyCombo.send(combo)
        case .shortcut(let name): Shortcuts.run(name)
        case .previousApp: MainActor.assumeIsolated { AppSwitcher.shared.switchToPrevious() }
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
            NSLog("TapShortcuts: не удалось выполнить \(tool): \(error)")
        }
    }
}
