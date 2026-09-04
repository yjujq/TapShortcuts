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
        entries += SystemAction.allCases.map {
            ActionEntry(tag: "system:" + $0.rawValue, title: $0.title, group: "System")
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
    let entries: [ActionEntry]

    @State private var choosing = false

    var body: some View {
        HStack {
            if gesture.conflictsWithSystem {
                // Mark the ones the system claims: they can be bound, but
                // they will not always fire.
                Label(gesture.title, systemImage: "exclamationmark.triangle")
            } else {
                Text(gesture.title)
            }
            Spacer(minLength: 8)
            Button {
                choosing = true
            } label: {
                HStack(spacing: 3) {
                    Text(ActionCatalogue.title(of: tag, in: entries))
                        .lineLimit(1)
                        .foregroundStyle(tag.isEmpty ? .secondary : .primary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $choosing, arrowEdge: .bottom) {
                ActionChooser(entries: entries, tag: $tag, showing: $choosing)
            }
        }
    }
}

/// The chooser: a search field and the filtered list side by side, so what
/// was found is visible.
private struct ActionChooser: View {
    let entries: [ActionEntry]
    @Binding var tag: String
    @Binding var showing: Bool

    @State private var search = ""
    @FocusState private var focused: Bool

    private var groups: [String] {
        var seen: [String] = []
        for e in filtered where !seen.contains(e.group) { seen.append(e.group) }
        return seen
    }

    private var filtered: [ActionEntry] {
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.title.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search actions", text: $search)
                    .textFieldStyle(.plain)
                    .focused($focused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            Divider()

            List {
                Button("— none —") { choose("") }
                    .buttonStyle(.plain)
                ForEach(groups, id: \.self) { group in
                    Section(group) {
                        ForEach(filtered.filter { $0.group == group }) { entry in
                            Button(entry.title) { choose(entry.tag) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if filtered.isEmpty {
                    Text("Nothing found").foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 320, height: 380)
        .panelChrome()
        .clearPopoverBackground()
        .onAppear { focused = true }
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
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain)
                    .focused($focused)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            Divider()

            List {
                ForEach(filtered, id: \.bundleID) { app in
                    Button(app.name) {
                        onPick(app.bundleID)
                        showing = false
                    }
                    .buttonStyle(.plain)
                }
                if filtered.isEmpty {
                    Text("Nothing found").foregroundStyle(.secondary)
                }
            }
            .listStyle(.inset)
        }
        .frame(width: 280, height: 320)
        .onAppear { focused = true }
    }
}
