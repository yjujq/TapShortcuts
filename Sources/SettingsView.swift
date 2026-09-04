import SwiftUI
import ApplicationServices

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var shortcuts: [String] = []
    @State private var apps: [(name: String, bundleID: String)] = []
    @State private var entries: [ActionEntry] = []
    @State private var addingExclusion = false
    @State private var loading = true
    @State private var accessibilityGranted = true

    /// Application name from its bundle identifier. One removed from the
    /// system is shown by its identifier, so it stays visible and removable.
    private func appName(_ bundleID: String) -> String {
        apps.first { $0.bundleID == bundleID }?.name ?? bundleID
    }

    private func isAssigned(_ gesture: Gesture) -> Bool {
        !(store.bindings[gesture.rawValue] ?? "").isEmpty
    }

    /// Bound gestures, in declaration order.
    private var assigned: [Gesture] {
        Gesture.allCases.filter(isAssigned)
    }

    /// Families in the order the gestures are declared.
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
                    Toggle("Guard against accidental triggers", isOn: $store.falseGuards)
                    if !store.falseGuards {
                        Text("Palm rejection and the pause after typing are off.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !store.showStatusIcon {
                        Text("Without the icon, reopen the app from Finder to get back here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Excluded apps") {
                    if store.excludedApps.isEmpty {
                        Text("Gestures work everywhere.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.excludedApps, id: \.self) { id in
                            HStack {
                                Text(appName(id))
                                Spacer()
                                Button {
                                    store.excludedApps.removeAll { $0 == id }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Add app…") { addingExclusion = true }
                        .controlSize(.small)
                        .popover(isPresented: $addingExclusion, arrowEdge: .bottom) {
                            AppChooser(apps: apps,
                                       exclude: store.excludedApps,
                                       onPick: { store.excludedApps.append($0) },
                                       showing: $addingExclusion)
                        }
                }

                if loading {
                    Section {
                        HStack { ProgressView().controlSize(.small); Text("Loading shortcuts…") }
                    }
                } else {
                    // Bound gestures go to the top: there are only a few of
                    // them, the whole list is long, and hunting for the bound
                    // ones every time would be tedious.
                    if !assigned.isEmpty {
                        Section("Assigned") {
                            ForEach(assigned) { gesture in
                                ActionPicker(gesture: gesture,
                                             tag: binding(for: gesture),
                                             entries: entries)
                            }
                        }
                    }

                    // Below, only the free ones, so bound ones do not appear twice.
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

            // Access is only needed for key combinations, so the hint appears
            // only once at least one of them is bound.
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

    /// The list is read in the background: calling the `shortcuts` tool takes
    /// noticeable time, and on the main thread the window would stall on open.
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

/// A standalone settings window. Needed when the menu bar icon is hidden:
/// a popover then has nothing to anchor to, so settings open in an ordinary
/// window when the app is relaunched from Finder.
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var escapeMonitor: Any?

    static func show() {
        if window == nil {
            // Borderless, so the window carries the same chrome as the panel
            // under the icon. A title bar would put a system-drawn strip above
            // our rounded corners and break the shape.
            let hosting = NSHostingView(
                rootView: AnyView(SettingsView(store: .shared).panelChrome())
            )
            hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)

            let w = NSWindow(
                contentRect: hosting.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            w.contentView = hosting
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.isReleasedWhenClosed = false
            // Without a title bar there is nothing to drag, so the background
            // itself moves the window, and Escape stands in for the close box.
            w.isMovableByWindowBackground = true
            w.center()
            window = w

            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                guard event.keyCode == 53 else { return event }   // 53 = Escape
                MainActor.assumeIsolated { close() }
                return nil
            }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        window?.orderOut(nil)
        window = nil
    }
}
