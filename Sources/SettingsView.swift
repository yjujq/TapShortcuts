import SwiftUI
import ApplicationServices

/// Where in the settings we are.
///
/// Everything used to live on one scroll: four switches, the exclusion list
/// and four dozen gesture rows below them. The header already printed
/// "Settings → Gestures", but the path was painted on — there was nowhere
/// else to be. Now it is real.
enum SettingsPage: Hashable {
    case root
    case general
    case exclusions
    case gestures
}

/// Which gestures the list shows.
enum GestureFilter: Hashable {
    case all, bound, free
}

struct SettingsView: View {
    @ObservedObject var store: Store

    @State private var page: SettingsPage = .root
    @State private var filter: GestureFilter = .all

    @State private var shortcuts: [String] = []
    @State private var apps: [(name: String, bundleID: String)] = []
    @State private var entries: [ActionEntry] = []
    @State private var addingExclusion = false
    @State private var loading = true
    @State private var accessibilityGranted = true

    var body: some View {
        VStack(spacing: 0) {
            CrumbBar(crumbs: crumbs) { _ in
                // The path is never deeper than two, so the only crumb that is
                // ever a button is the root.
                page = .root
            }
            Hairline()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Access is only needed for key combinations, so the hint appears
            // only once at least one of them is bound.
            if store.needsAccessibility, !accessibilityGranted {
                Hairline()
                accessibilityNotice
            }

            Hairline()
            footer
        }
        .frame(width: Chrome.width, height: Chrome.height)
        .background(shortcutKeys)
        .onAppear {
            load()
            accessibilityGranted = AXIsProcessTrusted()
        }
    }

    // MARK: - Chrome

    private var crumbs: [String] {
        switch page {
        case .root:       return ["Settings"]
        case .general:    return ["Settings", "General"]
        case .exclusions: return ["Settings", "Excluded apps"]
        case .gestures:   return ["Settings", "Gestures"]
        }
    }


    /// The shortcuts are not advertised anywhere in the panel — ⌘[ back a
    /// level, Escape to close, the latter caught by the panel's own monitor.
    /// They still work; they are parked behind the panel where they cannot be
    /// seen. A Button is the only way to bind a key without a menu.
    private var shortcutKeys: some View {
        ZStack {
            Button("") { page = .root }
                .keyboardShortcut("[", modifiers: .command)
        }
        // Invisible, but not zero-sized and not .hidden(): a view taken out of
        // the layout stops answering its shortcut. Sitting in a background it
        // costs the panel no space either way.
        .opacity(0)
    }

    /// The shelf along the bottom.
    ///
    /// These two are the app's only way out and its only way to refresh the
    /// action list, and it has no menu of any kind, so they belong where they
    /// can be reached from wherever you are rather than on the landing page, a
    /// level away. They sat in a footer once before as text links and went
    /// unnoticed; as pills on their own band they do not.
    private var footer: some View {
        HStack(spacing: 8) {
            PillButton(title: "Reload action list", symbol: "arrow.clockwise") {
                load()
            }
            Spacer()
            // Not marked destructive: red made it the loudest thing on the
            // panel, and quitting a menu bar app is ordinary, not dangerous.
            PillButton(title: "Quit", symbol: "power") {
                NSApp.terminate(nil)
            }
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 8)
        .background(Chrome.band)
    }

    private var accessibilityNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.dim)
            Text("Key combinations need Accessibility access.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.dim)
            Spacer(minLength: 8)
            PillButton(title: "Open settings") { openAccessibility() }
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 8)
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .root:       rootPage
        case .general:    generalPage
        case .exclusions: exclusionsPage
        case .gestures:   gesturesPage
        }
    }

    private var rootPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                NavRow(title: "General",
                       subtitle: "Enabled, login, menu bar icon, guards",
                       symbol: "switch.2") { page = .general }
                NavRow(title: "Excluded apps",
                       subtitle: "Where gestures stay silent",
                       symbol: "nosign",
                       badge: store.excludedApps.isEmpty
                           ? nil : "\(store.excludedApps.count)") { page = .exclusions }
                NavRow(title: "Gestures",
                       subtitle: "What each gesture runs",
                       symbol: "hand.tap",
                       badge: "\(boundCount)/\(Gesture.allCases.count)") { page = .gestures }

            }
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private var generalPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionHeader(title: "Gestures")
                SettingRow(title: "Enabled", toggle: $store.enabled)
                SettingRow(title: "Guard against accidental triggers",
                           subtitle: store.falseGuards
                               ? nil
                               : "Palm rejection and the pause after typing are off.",
                           toggle: $store.falseGuards)

                SectionHeader(title: "System")
                SettingRow(title: "Launch at login", toggle: $store.launchAtLogin)
                SettingRow(title: "Show icon in the menu bar",
                           subtitle: store.showStatusIcon
                               ? nil
                               : "Without the icon, reopen the app from Finder to get back here.",
                           toggle: $store.showStatusIcon)
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var exclusionsPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                SectionHeader(title: "Excluded apps",
                              trailing: store.excludedApps.isEmpty
                                  ? nil : "\(store.excludedApps.count)")
                if store.excludedApps.isEmpty {
                    HintText(text: "Gestures work everywhere. Add an app where the trackpad is already spoken for — a drawing tool or a game that reads multi-finger touches itself.")
                } else {
                    ForEach(store.excludedApps, id: \.self) { id in
                        ExclusionRow(name: appName(id)) {
                            store.excludedApps.removeAll { $0 == id }
                        }
                    }
                }

                HStack {
                    PillButton(title: "Add app…", symbol: "plus") { addingExclusion = true }
                        .popover(isPresented: $addingExclusion, arrowEdge: .bottom) {
                            AppChooser(apps: apps,
                                       exclude: store.excludedApps,
                                       onPick: { store.excludedApps.append($0) },
                                       showing: $addingExclusion)
                        }
                    Spacer()
                }
                .padding(.horizontal, Chrome.gutter)
                .padding(.top, 8)
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    private var gesturesPage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Segmented(options: [(GestureFilter.all, "All"),
                                    (.bound, "Bound"),
                                    (.free, "Free")],
                          selection: $filter)
                Spacer(minLength: 8)
                Text("\(boundCount) of \(Gesture.allCases.count) bound")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Chrome.faint)
            }
            .padding(.horizontal, Chrome.gutter)
            .padding(.vertical, 8)
            Hairline()

            ScrollView {
                VStack(spacing: 0) {
                    if loading {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Loading shortcuts…")
                                .font(.system(size: 12))
                                .foregroundStyle(Chrome.dim)
                        }
                        .padding(.horizontal, Chrome.gutter)
                        .padding(.vertical, 14)
                    } else {
                        gestureList
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var gestureList: some View {
        // Bound gestures go to the top: there are only a few of them, the
        // whole list is long, and hunting for the bound ones every time would
        // be tedious. The filter above can drop either half outright.
        if filter != .free, !assigned.isEmpty {
            SectionHeader(title: "Assigned")
            ForEach(assigned) { gesture in
                gestureRow(gesture)
            }
        }

        if filter != .bound {
            // Below, only the free ones, so bound ones do not appear twice.
            ForEach(families, id: \.self) { family in
                let free = Gesture.allCases.filter {
                    $0.family == family && !isAssigned($0)
                }
                if !free.isEmpty {
                    SectionHeader(title: family)
                    ForEach(free) { gesture in
                        gestureRow(gesture)
                    }
                }
            }
        }

        if isListEmpty {
            HintText(text: "Nothing to show with this filter.")
                .padding(.top, 14)
        }
    }

    private func gestureRow(_ gesture: Gesture) -> some View {
        ActionPicker(gesture: gesture,
                     tag: binding(for: gesture),
                     entries: entries)
    }

    // MARK: - The gesture list, filtered

    private var boundCount: Int {
        Gesture.allCases.filter { isAssigned($0) }.count
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

    private var isListEmpty: Bool {
        let showsBound = filter != .free && !assigned.isEmpty
        let showsFree = filter != .bound && !families.isEmpty
        return !showsBound && !showsFree
    }

    // MARK: -

    /// Application name from its bundle identifier. One removed from the
    /// system is shown by its identifier, so it stays visible and removable.
    private func appName(_ bundleID: String) -> String {
        apps.first { $0.bundleID == bundleID }?.name ?? bundleID
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

/// One excluded application, with the way to take it off the list.
private struct ExclusionRow: View {
    let name: String
    let remove: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(Chrome.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(hovered ? Chrome.text : Chrome.faint)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 6)
        .background(hovered ? Chrome.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
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
