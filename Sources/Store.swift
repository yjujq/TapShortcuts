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

    @Published var launchAtLogin = false {
        didSet { LoginItem.set(launchAtLogin) }
    }

    private let defaults = UserDefaults.standard
    private let key = "bindings.v2"

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
        launchAtLogin = LoginItem.isEnabled
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
