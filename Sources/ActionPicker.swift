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
                ActionChooser(entries: entries, tag: $tag, showing: $choosing)
            }
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 5)
        .background(hovered ? Chrome.hover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
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
            SearchRow(text: $search, placeholder: "Search actions", focused: $focused) {
                EmptyView()
            }
            Hairline()

            ScrollView {
                VStack(spacing: 0) {
                    // Clearing the binding sits above the groups rather than
                    // inside one: it belongs to no family of actions.
                    ChooserRow(title: "— none —", isSelected: tag.isEmpty) { choose("") }

                    ForEach(groups, id: \.self) { group in
                        SectionHeader(title: group)
                        ForEach(filtered.filter { $0.group == group }) { entry in
                            ChooserRow(title: entry.title,
                                       isSelected: entry.tag == tag) { choose(entry.tag) }
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
