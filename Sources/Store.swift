import AppKit

/// Настройки: какому жесту какая команда назначена.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// Жест -> имя команды. Пустое имя означает «жест не занят».
    @Published var bindings: [String: String] = [:] {
        didSet { defaults.set(bindings, forKey: key) }
    }

    @Published var enabled = true {
        didSet { defaults.set(enabled, forKey: "enabled") }
    }

    @Published var showStatusIcon = true {
        didSet { defaults.set(showStatusIcon, forKey: "showStatusIcon") }
    }

    /// Защита от ложных срабатываний: отсев ладони, молчание при наборе
    /// текста и при зажатой кнопке мыши.
    @Published var falseGuards = true {
        didSet { defaults.set(falseGuards, forKey: "falseGuards") }
    }

    /// Приложения, в которых жесты не срабатывают, по опознавателям.
    ///
    /// Нужны там, где трекпад занят своим: чертёжные и игровые программы
    /// толкуют многопальцевые касания сами, и наш перехват им мешает.
    @Published var excludedApps: [String] = [] {
        didSet { defaults.set(excludedApps, forKey: excludedKey) }
    }

    @Published var launchAtLogin = false {
        didSet { LoginItem.set(launchAtLogin) }
    }

    private let defaults = UserDefaults.standard
    private let key = "bindings.v2"
    private let excludedKey = "excludedApps.v1"

    private init() {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        showStatusIcon = defaults.object(forKey: "showStatusIcon") as? Bool ?? true
        // По умолчанию заняты только два боковых жеста — с них и начали.
        //
        // Пустой словарь считаем ненастроенным наравне с отсутствующим:
        // иначе однажды записанная пустота навсегда отменила бы значения
        // по умолчанию. И записываем явно — наблюдатель свойства внутри
        // инициализатора не срабатывает.
        let stored = defaults.dictionary(forKey: key) as? [String: String]
        if let stored, !stored.isEmpty {
            bindings = stored
        } else {
            bindings = [
                Gesture.tipRight.rawValue: "keys:cmd+w",
                Gesture.tipLeft.rawValue: "system:previousApp",
            ]
            defaults.set(bindings, forKey: key)
        }
        falseGuards = defaults.object(forKey: "falseGuards") as? Bool ?? true
        excludedApps = defaults.stringArray(forKey: excludedKey) ?? []
        launchAtLogin = LoginItem.isEnabled
    }

    /// Исключено ли приложение, которое сейчас впереди.
    ///
    /// Спрашиваем систему в момент жеста, а не следим за сменой приложения:
    /// жесты редки, а слежение означало бы лишнюю подписку на каждое
    /// переключение окна.
    var frontmostIsExcluded: Bool {
        guard !excludedApps.isEmpty,
              let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return false }
        return excludedApps.contains(id)
    }

    func action(for gesture: Gesture) -> Action {
        Action.decode(bindings[gesture.rawValue] ?? "")
    }

    /// Нужен ли доступ к Универсальному управлению: только для сочетаний
    /// клавиш. Запуск быстрых команд обходится без него.
    var needsAccessibility: Bool {
        bindings.values.contains { $0.hasPrefix("keys:") }
    }
}
