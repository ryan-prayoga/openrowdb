// ShortcutsHelpView.swift
import SwiftUI

/// Reference sheet listing all keyboard shortcuts, grouped by context.
/// Opened via Help → Keyboard Shortcuts… (⌘/).
struct ShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct ShortcutEntry: Identifiable {
        let id = UUID()
        let keys: [String]
        let description: String
    }

    private struct ShortcutGroup: Identifiable {
        let id = UUID()
        let title: String
        let entries: [ShortcutEntry]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "General", entries: [
            ShortcutEntry(keys: ["⌘", "N"], description: "New connection"),
            ShortcutEntry(keys: ["⌘", "W"], description: "Close current tab"),
            ShortcutEntry(keys: ["⌘", "T"], description: "New query tab"),
        ]),
        ShortcutGroup(title: "Query Editor", entries: [
            ShortcutEntry(keys: ["⌘", "↩"], description: "Run query"),
            ShortcutEntry(keys: ["⌘", "."], description: "Cancel in-flight query"),
            ShortcutEntry(keys: ["Tab"], description: "Trigger autocomplete"),
            ShortcutEntry(keys: ["⌘", "F"], description: "Find in editor"),
        ]),
        ShortcutGroup(title: "Browse / Table Viewer", entries: [
            ShortcutEntry(keys: ["⌘", "R"], description: "Refresh sidebar, row counts, and current table page"),
        ]),
        ShortcutGroup(title: "Table Viewer — Row Editing", entries: [
            ShortcutEntry(keys: ["⌘", "↩"], description: "Save inline edit or insert row"),
            ShortcutEntry(keys: ["Esc"], description: "Cancel inline edit or insert panel"),
        ]),
        ShortcutGroup(title: "Sidebar", entries: [
            ShortcutEntry(keys: ["↩", "↩"], description: "Double-click connection to connect"),
        ]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 460, height: 500)
    }

    private var header: some View {
        HStack {
            Label("Keyboard Shortcuts", systemImage: "keyboard")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var content: some View {
        List {
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.entries) { entry in
                        shortcutRow(entry)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func shortcutRow(_ entry: ShortcutEntry) -> some View {
        HStack {
            Text(entry.description)
                .font(.callout)
            Spacer()
            HStack(spacing: 3) {
                ForEach(entry.keys, id: \.self) { key in
                    Text(key)
                        .font(.system(.caption, design: .rounded).weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: .rect(cornerRadius: 5))
                }
            }
        }
        .padding(.vertical, 1)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    ShortcutsHelpView()
}
