import SwiftUI

/// Одно доступное действие в общем перечне.
struct ActionEntry: Identifiable, Hashable {
    let tag: String
    let title: String
    let group: String
    var id: String { tag }
}

/// Общий перечень действий. Собирается один раз при открытии настроек
/// и служит и для показа назначенного, и для поиска.
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

    /// Как назвать назначенное. Для вписанных вручную команд оболочки
    /// и сценариев показываем их самих — в перечне их нет.
    static func title(of tag: String, in entries: [ActionEntry]) -> String {
        if tag.isEmpty { return "— none —" }
        if let found = entries.first(where: { $0.tag == tag }) { return found.title }
        if tag.hasPrefix("shell:") { return "Shell: " + tag.dropFirst(6) }
        if tag.hasPrefix("script:") { return "Script" }
        return tag
    }
}

/// Строка жеста: слева название, справа назначенное действие.
/// Щелчок по действию открывает окошко выбора с поиском.
struct ActionPicker: View {
    let gesture: Gesture
    @Binding var tag: String
    let entries: [ActionEntry]

    @State private var choosing = false

    var body: some View {
        HStack {
            if gesture.conflictsWithSystem {
                // Помечаем занятые системой: назначить можно, но срабатывать
                // будет не всегда.
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

/// Окошко выбора: поле поиска и отобранный список рядом, так что видно,
/// что именно нашлось.
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
        .onAppear { focused = true }
    }

    private func choose(_ newTag: String) {
        tag = newTag
        showing = false
    }
}
