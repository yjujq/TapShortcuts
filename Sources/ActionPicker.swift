import SwiftUI

/// A single available action in the shared catalogue.
struct ActionEntry: Identifiable, Hashable {
    let tag: String
    let title: String
    let group: String
    var id: String { tag }
}

/// The shared catalogue of actions. Built once when settings open and used
/// both to display the current binding and to search.
enum ActionCatalogue {
    static func all(shortcuts: [String],
                    apps: [(name: String, bundleID: String)]) -> [ActionEntry] {
        var entries: [ActionEntry] = [
            ActionEntry(tag: "system:previousApp", title: "Previous app", group: "System")
        ]
        entries += SystemAction.allCases.map { action in
            // A system shortcut switched off in System Settings is still
            // offered, but says so: sent, it would go nowhere without a word.
            let off = action.hotKey.map { !$0.isOn } ?? false
            return ActionEntry(tag: "system:" + action.rawValue,
                               title: off ? action.title + " — off in System Settings"
                                          : action.title,
                               group: "System")
        }
        entries += KeyCombo.presets.map {
            ActionEntry(tag: "keys:" + $0.combo, title: $0.title, group: "Keys")
        }
        entries += apps.map {
            ActionEntry(tag: "app:" + $0.bundleID, title: "Open " + $0.name, group: "Apps")
        }
        entries += shortcuts.map {
            ActionEntry(tag: "shortcut:" + $0, title: $0, group: "Shortcuts")
        }
        return entries
    }

    /// How to name the current binding. Hand-written shell commands and
    /// scripts are shown as themselves — they are not in the catalogue.
    static func title(of tag: String, in entries: [ActionEntry]) -> String {
        if tag.isEmpty { return "— none —" }
        if let found = entries.first(where: { $0.tag == tag }) { return found.title }
        if tag.hasPrefix("keys:") {
            // Recorded, or written by hand into the defaults: shown the way
            // the system prints a shortcut, and flagged when it names a key
            // that no layout here types — sent, it would go nowhere.
            let combo = String(tag.dropFirst(5))
            let shown = KeyCombo.display(combo)
            return KeyCombo.resolve(combo) == nil ? shown + " — unknown key" : shown
        }
        if tag.hasPrefix("shell:") { return "Shell: " + tag.dropFirst(6) }
        if tag.hasPrefix("script:") { return "Script" }
        return tag
    }
}

/// A gesture row: the name on the left, the bound action on the right.
/// Clicking the action opens a chooser with search.
struct ActionPicker: View {
    let gesture: Gesture
    @Binding var tag: String
    /// The gesture's own haptic strength; nil follows the default.
    @Binding var haptic: HapticStrength?
    let entries: [ActionEntry]

    @State private var choosing = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            if gesture.conflictsWithSystem {
                // Mark the ones the system claims: they can be bound, but
                // they will not always fire.
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Chrome.faint)
                    .help("The system claims this gesture; it will not always fire.")
            }
            Text(gesture.title)
                .font(.system(size: 13))
                .foregroundStyle(Chrome.text)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let haptic {
                // A gesture whose knock differs from the default says so, or
                // there would be no telling which ones do without opening each.
                Image(systemName: haptic == .off ? "waveform.slash" : "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(Chrome.faint)
                    .help("Haptic: \(haptic.title)")
            }

            Button { choosing = true } label: {
                HStack(spacing: 4) {
                    Text(ActionCatalogue.title(of: tag, in: entries))
                        .font(.system(size: 12))
                        .foregroundStyle(tag.isEmpty ? Chrome.faint : Chrome.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Chrome.faint)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Chrome.fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Chrome.hairline, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $choosing, arrowEdge: .bottom) {
                ActionChooser(entries: entries, tag: $tag, haptic: $haptic, showing: $choosing)
            }
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 5)
        .background(hovered ? Chrome.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}


/// Set while a chooser is open, so the panels' own Escape handling stands
/// aside. Escape then closes the chooser, or cancels a recording inside it,
/// rather than closing the whole panel around it — which is what it used to
/// do, taking the settings down with it.
enum EscapeOwner {
    static var claimed = false
}

/// The chooser: a search field and the filtered list side by side, so what
/// was found is visible. It can also record a key combination of its own, or
/// take one typed in where recording cannot see it.
private struct ActionChooser: View {
    let entries: [ActionEntry]
    @Binding var tag: String
    @Binding var haptic: HapticStrength?
    @Binding var showing: Bool

    private enum Mode { case list, recording, typing }

    @State private var mode: Mode = .list
    @State private var search = ""
    @FocusState private var focused: Bool

    @State private var monitor: Any?
    @State private var held: NSEvent.ModifierFlags = []
    /// Every modifier held since the last moment none were.
    @State private var peak: NSEvent.ModifierFlags = []
    /// The modifiers of a press that ended with no key arriving.
    ///
    /// That is the sign of a shortcut another application owns: the system
    /// hands the key to its owner and to nobody else, while the modifiers flow
    /// on as usual. Measured with DeepL's ⌘⇧2 — ⌘ and ⇧ reached the recorder,
    /// the 2 never did.
    @State private var swallowed: NSEvent.ModifierFlags?

    @State private var typed = ""

    /// Which row the keyboard is on, as an index into `choices`. Hovering
    /// moves it too, so the mouse and the keyboard never light two rows at
    /// once — which was the whole of the trouble.
    @State private var highlighted = 0
    /// Bumped whenever the keyboard moves the highlight, and only then.
    @State private var scrollTick = 0

    private var groups: [String] {
        var seen: [String] = []
        for e in filtered where !seen.contains(e.group) { seen.append(e.group) }
        return seen
    }

    private var filtered: [ActionEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    /// What the list can land on, in the order it is drawn.
    private enum Choice: Equatable {
        case clear
        case record
        case entry(String)
    }

    /// One drawn line: a group heading, or a row with its place in `choices`.
    ///
    /// Headings and rows are built into one list rather than laid out as the
    /// list is drawn, so the keyboard's idea of the order and what is on
    /// screen cannot fall out of step.
    private struct Line: Identifiable {
        let id: String
        var header: String? = nil
        var choice: Choice? = nil
        var index: Int? = nil
        var title = ""
        var isSelected = false
    }

    private var lines: [Line] {
        var out: [Line] = []
        var index = 0
        func row(_ choice: Choice, _ title: String, _ isSelected: Bool) {
            out.append(Line(id: "row-\(index)", choice: choice, index: index,
                            title: title, isSelected: isSelected))
            index += 1
        }
        // Clearing the binding and recording one sit above the groups rather
        // than inside one: they belong to no family of actions.
        row(.clear, "— none —", tag.isEmpty)
        row(.record,
            customCombo.map { KeyCombo.display($0) + " — record again…" }
                ?? "Record a key combination…",
            customCombo != nil)
        for group in groups {
            out.append(Line(id: "head-" + group, header: group))
            for entry in filtered where entry.group == group {
                row(.entry(entry.tag), entry.title, entry.tag == tag)
            }
        }
        return out
    }

    private var choices: [Choice] { lines.compactMap(\.choice) }

    /// Where the highlight starts: on the action the gesture already has, so
    /// opening the chooser and pressing Return changes nothing. Landing on
    /// "— none —" instead, it would have cleared the binding.
    private var currentIndex: Int? {
        choices.firstIndex { choice in
            switch choice {
            case .clear:            return tag.isEmpty
            case .record:           return customCombo != nil
            case .entry(let entry): return entry == tag
            }
        }
    }

    private var firstEntryIndex: Int? {
        choices.firstIndex { if case .entry = $0 { return true } else { return false } }
    }

    private func activate(_ choice: Choice) {
        switch choice {
        case .clear:            choose("")
        case .record:           startRecording()
        case .entry(let entry): choose(entry)
        }
    }

    private func move(_ delta: Int) {
        let count = choices.count
        guard count > 0 else { return }
        // Clamped rather than wrapped: at the end of a long list, an arrow
        // that jumped back to the top would lose the eye.
        highlighted = min(max(highlighted + delta, 0), count - 1)
        scrollTick += 1
    }

    /// A key combination bound here that is none of the ready ones.
    private var customCombo: String? {
        guard tag.hasPrefix("keys:"), !entries.contains(where: { $0.tag == tag }) else { return nil }
        return String(tag.dropFirst(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            switch mode {
            case .list:      list
            case .recording: recorder
            case .typing:    typer
            }
        }
        // 360 rather than 320: the haptic strip below needs 285 points for its
        // five segments — measured, not guessed — and at 320 it did not fit.
        .frame(width: 360, height: 380)
        .panelChrome()
        .clearPopoverBackground()
        .onAppear {
            focused = true
            highlighted = currentIndex ?? 0
            EscapeOwner.claimed = true
            installMonitor()
        }
        // The popover can close under a recording — a click outside does it —
        // and a monitor left behind would swallow every key the app receives.
        .onDisappear { teardown() }
    }

    // MARK: - The list

    private var list: some View {
        VStack(spacing: 0) {
            SearchRow(text: $search, placeholder: "Search actions", focused: $focused) {
                EmptyView()
            }
            Hairline()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(lines) { line in
                            if let header = line.header {
                                SectionHeader(title: header)
                            } else if let choice = line.choice, let index = line.index {
                                ChooserRow(title: line.title,
                                           isSelected: line.isSelected,
                                           isHighlighted: index == highlighted) {
                                    activate(choice)
                                }
                                .id(index)
                            }
                        }

                        if filtered.isEmpty {
                            HintText(text: "Nothing matches “\(search)”.")
                                .padding(.top, 14)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                // Driven by the tick rather than by the highlight itself, so
                // only the arrows scroll. Watching the highlight dragged the
                // list around under the pointer as the mouse crossed rows.
                // A counter rather than the index: two presses landing on the
                // same row still each ask for a scroll.
                .onChange(of: scrollTick) { _, _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(highlighted, anchor: .center)
                    }
                }
            }
            .onChange(of: search) { _, _ in
                // After a query the row worth landing on is the first match,
                // not "— none —" at the top.
                highlighted = search.isEmpty ? 0 : (firstEntryIndex ?? 0)
                scrollTick += 1
            }

            // The gesture's own knock sits here, where the gesture is set up,
            // rather than as a column on every row of the long list. Choosing
            // a strength plays it and leaves the list open.
            Hairline()
            HStack(spacing: 10) {
                Text("Haptic")
                    .font(.system(size: 12))
                    .foregroundStyle(Chrome.dim)
                Spacer(minLength: 0)
                Segmented(options: [(value: nil, label: "Default")]
                                   + HapticStrength.allCases.map { (value: Optional($0), label: $0.title) },
                          selection: $haptic)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Chrome.band)
        }
    }

    // MARK: - Recording

    private var recorder: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(held.isEmpty ? "Press a key combination" : KeyCombo.glyphs(for: held))
                .font(.system(size: held.isEmpty ? 15 : 30, weight: .medium))
                .foregroundStyle(Chrome.text)
            if let swallowed, held.isEmpty {
                Text("Only \(KeyCombo.glyphs(for: swallowed)) arrived — the key itself went to another app, which owns this shortcut. Type it in instead.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.dim)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text("Esc cancels.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.dim)
                // Said up front, or the recorder would look broken: these are
                // taken by the system before any application sees them.
                Text("Shortcuts the system or another app keeps for itself, such as ⌘⇥ or ⌘Space, never reach here.")
                    .font(.system(size: 11))
                    .foregroundStyle(Chrome.faint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()
            HStack(spacing: 8) {
                PillButton(title: "Type it in") { beginTyping() }
                Spacer()
                PillButton(title: "Cancel") { backToList() }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startRecording() {
        held = []
        peak = []
        swallowed = nil
        mode = .recording
    }

    /// One monitor for the whole chooser, for as long as it is open.
    ///
    /// A local monitor sees a key before the menus and the panel do — which is
    /// what lets the list answer the arrows while the search field holds
    /// focus, and lets a recorded ⌘W or ⌘Q be captured instead of acted on.
    /// It is called on the main thread, which is what makes the assertion
    /// below sound — unlike the trackpad thread, where the same assertion once
    /// crashed the app.
    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Plain values go in and a verdict comes out: NSEvent is not
            // Sendable, so it cannot be handed back across the assertion.
            let isModifierChange = event.type == .flagsChanged
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection([.control, .option, .shift, .command])
            let swallow = MainActor.assumeIsolated {
                handle(isModifierChange: isModifierChange, keyCode: keyCode, modifiers: modifiers)
            }
            return swallow ? nil : event
        }
    }

    /// Takes one key event; returns whether to swallow it.
    private func handle(isModifierChange: Bool, keyCode: UInt16,
                        modifiers: NSEvent.ModifierFlags) -> Bool {
        switch mode {
        case .recording:
            return record(isModifierChange: isModifierChange, keyCode: keyCode, modifiers: modifiers)

        case .typing:
            // The field handles its own keys; only Escape is taken, to go back
            // a step rather than close the chooser outright.
            guard !isModifierChange, keyCode == 53 else { return false }   // 53 = Escape
            backToList()
            return true

        case .list:
            // A modifier held means a shortcut, not navigation: ⌘A in the
            // search field must still select its text.
            guard !isModifierChange, modifiers.isEmpty else { return false }
            switch keyCode {
            case 126: move(-1); return true                // up
            case 125: move(1);  return true                // down
            case 36, 76:                                   // return, keypad enter
                let list = choices
                guard highlighted >= 0, highlighted < list.count else { return true }
                activate(list[highlighted])
                return true
            case 53:                                       // Escape
                // Closes the chooser alone. The panel's own Escape stands
                // aside meanwhile, or the settings would go down with it.
                showing = false
                return true
            default:
                return false
            }
        }
    }

    /// Takes one key event while recording; returns whether to swallow it.
    private func record(isModifierChange: Bool, keyCode: UInt16,
                        modifiers: NSEvent.ModifierFlags) -> Bool {
        if isModifierChange {
            if held.isEmpty, !modifiers.isEmpty { swallowed = nil }   // a new press begins
            held = modifiers
            peak.formUnion(modifiers)
            if modifiers.isEmpty {
                // Every modifier released and no key recorded in between.
                if !peak.isEmpty { swallowed = peak }
                peak = []
            }
            return false
        }
        // Escape alone cancels; with a modifier it is a combination like any
        // other.
        if keyCode == 53, modifiers.isEmpty {        // 53 = Escape
            backToList()
            return true
        }
        // A key with no name — keypad Enter, say — is swallowed, and the
        // recorder keeps waiting for one it can store.
        guard let combo = KeyCombo.describe(code: CGKeyCode(keyCode), modifiers: modifiers) else {
            return true
        }
        bind(combo)
        return true
    }

    // MARK: - Typing

    private var typer: some View {
        VStack(spacing: 12) {
            Spacer()
            TextField("cmd+shift+2", text: $typed)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Chrome.text)
                .multilineTextAlignment(.center)
                .focused($focused)
                .onSubmit { bindTyped() }
                .onExitCommand { backToList() }
                .padding(.horizontal, 24)
                .onAppear { DispatchQueue.main.async { focused = true } }
            Text(typedPreview)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Chrome.text)
            Text(typedCombo == nil && !typedTrimmed.isEmpty
                 ? "Not a key combination yet."
                 : "cmd, shift, alt and ctrl, then the key, joined with +. Return binds it.")
                .font(.system(size: 11))
                .foregroundStyle(Chrome.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            HStack(spacing: 8) {
                PillButton(title: "Back") { backToList() }
                Spacer()
                PillButton(title: "Bind") { bindTyped() }
                    .disabled(typedCombo == nil)
                    .opacity(typedCombo == nil ? 0.4 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var typedTrimmed: String {
        typed.lowercased().replacingOccurrences(of: " ", with: "")
    }

    /// The typed combination when it names something sendable, else nil.
    private var typedCombo: String? {
        KeyCombo.resolve(typedTrimmed) == nil ? nil : typedTrimmed
    }

    private var typedPreview: String {
        typedCombo.map(KeyCombo.display) ?? " "
    }

    /// Leaves the recorder for the text field. The Escape guard stays on: the
    /// field's own Escape goes back to the list, and the panel around it must
    /// not close instead.
    private func beginTyping() {
        held = []
        // What the recorder did catch is kept, so only the key is left to type.
        typed = swallowed.map { prefix(for: $0) } ?? ""
        mode = .typing
    }

    /// Modifiers written the way a combination begins: "shift+cmd+".
    private func prefix(for modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option)  { parts.append("alt") }
        if modifiers.contains(.shift)   { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        return parts.map { $0 + "+" }.joined()
    }

    private func bindTyped() {
        guard let combo = typedCombo else { return }
        bind(combo)
    }

    // MARK: -

    private func bind(_ combo: String) {
        let newTag = readyTag(for: combo) ?? "keys:" + combo
        backToList()
        choose(newTag)
    }

    /// The ready entry that sends the same thing, if there is one, so the list
    /// shows it ticked rather than a lookalike stored under another spelling.
    private func readyTag(for combo: String) -> String? {
        guard let recorded = KeyCombo.resolve(combo) else { return nil }
        return entries.first { entry in
            guard entry.tag.hasPrefix("keys:"),
                  let ready = KeyCombo.resolve(String(entry.tag.dropFirst(5))) else { return false }
            return ready.code == recorded.code && ready.flags == recorded.flags
        }?.tag
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func backToList() {
        mode = .list
        held = []
        peak = []
        swallowed = nil
        typed = ""
    }

    /// The chooser is going away, so the monitor goes with it — left behind,
    /// it would swallow every key the application receives afterwards.
    private func teardown() {
        removeMonitor()
        EscapeOwner.claimed = false
        backToList()
    }

    private func choose(_ newTag: String) {
        tag = newTag
        showing = false
    }
}

/// Picking an application from the installed ones, with search.
/// Used for the exclusion list.
struct AppChooser: View {
    let apps: [(name: String, bundleID: String)]
    /// Already chosen ones are hidden: there is no point adding them twice.
    let exclude: [String]
    let onPick: (String) -> Void
    @Binding var showing: Bool

    @State private var search = ""
    @FocusState private var focused: Bool

    private var filtered: [(name: String, bundleID: String)] {
        apps.filter { app in
            guard !exclude.contains(app.bundleID) else { return false }
            guard !search.isEmpty else { return true }
            return app.name.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchRow(text: $search, placeholder: "Search apps", focused: $focused) {
                EmptyView()
            }
            Hairline()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(filtered, id: \.bundleID) { app in
                        ChooserRow(title: app.name) {
                            onPick(app.bundleID)
                            showing = false
                        }
                    }
                    if filtered.isEmpty {
                        HintText(text: search.isEmpty
                                 ? "Every installed app is already on the list."
                                 : "Nothing matches “\(search)”.")
                            .padding(.top, 14)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
        .frame(width: 300, height: 340)
        // The chooser used to come up in the system's own light plate: it was
        // the one surface in the app that had never been given the dark chrome.
        .panelChrome()
        .clearPopoverBackground()
        .onAppear { focused = true }
    }
}
