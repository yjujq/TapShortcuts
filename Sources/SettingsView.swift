import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var shortcuts: [String] = []
    @State private var apps: [(name: String, bundleID: String)] = []
    @State private var entries: [ActionEntry] = []
    @State private var loading = true
    @State private var accessibilityGranted = true

    private func isAssigned(_ gesture: Gesture) -> Bool {
        !(store.bindings[gesture.rawValue] ?? "").isEmpty
    }

    /// Занятые жесты в порядке объявления.
    private var assigned: [Gesture] {
        Gesture.allCases.filter(isAssigned)
    }

    /// Разделы в том порядке, в каком объявлены жесты.
    private var families: [String] {
        var seen: [String] = []
        for g in Gesture.allCases where !isAssigned(g) && !seen.contains(g.family) {
            seen.append(g.family)
        }
        return seen
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Enabled", isOn: $store.enabled)
                    Toggle("Launch at login", isOn: $store.launchAtLogin)
                    Toggle("Show icon in the menu bar", isOn: $store.showStatusIcon)
                    if !store.showStatusIcon {
                        Text("Without the icon, reopen the app from Finder to get back here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if loading {
                    Section {
                        HStack { ProgressView().controlSize(.small); Text("Loading shortcuts…") }
                    }
                } else {
                    // Занятые жесты выносим наверх: их единицы, а список
                    // целиком длинный, и каждый раз искать в нём назначенное
                    // было бы утомительно.
                    if !assigned.isEmpty {
                        Section("Assigned") {
                            ForEach(assigned) { gesture in
                                ActionPicker(gesture: gesture,
                                             tag: binding(for: gesture),
                                             entries: entries)
                            }
                        }
                    }

                    // Ниже — только свободные, чтобы занятые не двоились.
                    ForEach(families, id: \.self) { family in
                        let free = Gesture.allCases.filter {
                            $0.family == family && !isAssigned($0)
                        }
                        if !free.isEmpty {
                            Section(family) {
                                ForEach(free) { gesture in
                                    ActionPicker(gesture: gesture,
                                                 tag: binding(for: gesture),
                                                 entries: entries)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            // Доступ нужен только сочетаниям клавиш, поэтому и подсказка
            // появляется лишь когда хотя бы одно из них назначено.
            if store.needsAccessibility, !accessibilityGranted {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text("Key combinations need Accessibility access.")
                    Spacer()
                    Button("Open…") { openAccessibility() }
                }
                .font(.caption)
                .padding(8)
            }

            Divider()
            HStack {
                Button("Reload list") { load() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
            .padding(8)
        }
        .frame(width: 400, height: 520)
        .onAppear {
            load()
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    private func openAccessibility() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    private func binding(for gesture: Gesture) -> Binding<String> {
        Binding(
            get: { store.bindings[gesture.rawValue] ?? "" },
            set: { store.bindings[gesture.rawValue] = $0 }
        )
    }

    /// Список читается в фоне: обращение к программе `shortcuts` занимает
    /// заметное время, и на главном потоке окно бы подвисало при открытии.
    private func load() {
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let names = Shortcuts.list()
            let installed = Apps.list()
            DispatchQueue.main.async {
                shortcuts = names
                apps = installed
                entries = ActionCatalogue.all(shortcuts: names, apps: installed)
                loading = false
            }
        }
    }
}

/// Отдельное окно настроек. Нужно на случай, когда значок в строке меню
/// скрыт: тогда всплывающему окну не от чего оттолкнуться, и настройки
/// открываются обычным окном по повторному запуску из Finder.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: .shared))
            let w = NSWindow(contentViewController: hosting)
            w.title = "TapShortcuts"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
