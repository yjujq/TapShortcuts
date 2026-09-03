import AppKit

/// Settings: which action is bound to which gesture.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    /// Gesture -> action tag. An empty tag means the gesture is unbound.
    @Published var bindings: [String: String] = [:] {
        didSet { defaults.set(bindings, forKey: key) }
    }

    @Published var enabled = true {
        didSet { defaults.set(enabled, forKey: "enabled") }
    }

    @Published var showStatusIcon = true {
        didSet { defaults.set(showStatusIcon, forKey: "showStatusIcon") }
    }

    /// Guards against accidental triggers: palm rejection, plus silence while
    /// typing and while a mouse button is held.
    @Published var falseGuards = true {
        didSet { defaults.set(falseGuards, forKey: "falseGuards") }
    }

    /// Applications where gestures do not fire, by bundle identifier.
    ///
    /// Needed where the trackpad is already spoken for: drawing tools and
    /// games interpret multi-finger touches themselves, and our interception
    /// gets in their way.
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
        // Only the two side gestures are bound by default; they came first.
        //
        // An empty dictionary counts as unconfigured, same as a missing one:
        // otherwise emptiness written once would cancel the defaults forever.
        // And we write explicitly — a property observer does not fire inside
        // the initialiser.
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

    /// Whether the frontmost application is excluded.
    ///
    /// We ask the system at the moment of the gesture rather than watching
    /// for app changes: gestures are rare, and watching would mean a needless
    /// subscription to every window switch.
    var frontmostIsExcluded: Bool {
        guard !excludedApps.isEmpty,
              let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        else { return false }
        return excludedApps.contains(id)
    }

    func action(for gesture: Gesture) -> Action {
        Action.decode(bindings[gesture.rawValue] ?? "")
    }

    /// Whether Accessibility access is needed: only for key combinations.
    /// Running shortcuts does without it.
    var needsAccessibility: Bool {
        bindings.values.contains { $0.hasPrefix("keys:") }
    }
}
