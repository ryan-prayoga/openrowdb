// QueryHistoryView.swift
import OpenrowDBCore
import SwiftUI

/// Trailing inspector listing past queries for this connection, newest first.
/// Clicking an entry loads its SQL into the editor via the `onSelect` callback.
struct QueryHistoryView: View {
    @Environment(QueryHistoryStore.self) private var history
    @Environment(AppPreferences.self) private var preferences
    let connectionID: UUID
    let onSelect: (String) -> Void

    @State private var entries: [HistoryEntry] = []
    @State private var loadError: String?
    @State private var search = ""
    @State private var expandedEntryIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Label("History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                Menu {
                    Button("Clear for this connection", role: .destructive) {
                        Task {
                            try? await history.clear(connectionID: connectionID)
                            await reload()
                        }
                    }
                    Button("Clear all history", role: .destructive) {
                        Task {
                            try? await history.clearAll()
                            await reload()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("More")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                TextField("Search history", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()

            if let loadError {
                PlaceholderView(
                    title: "History unavailable",
                    subtitle: loadError,
                    systemImage: "exclamationmark.triangle",
                    variant: .error
                )
            } else if filteredEntries.isEmpty {
                PlaceholderView(
                    title: search.isEmpty ? "No history yet" : "No matches",
                    subtitle: search.isEmpty
                        ? "Run a query to populate this list."
                        : "Try a different search term.",
                    systemImage: search.isEmpty ? "tray" : "magnifyingglass"
                )
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        entryRow(entry)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onSelect(entry.sql) }
                            .onTapGesture(count: 1) { toggleExpanded(entry.id) }
                            .contextMenu {
                                Button("Load into editor") { onSelect(entry.sql) }
                                Button(expandedEntryIDs.contains(entry.id) ? "Collapse" : "Expand") {
                                    toggleExpanded(entry.id)
                                }
                                Button("Delete", role: .destructive) {
                                    Task {
                                        try? await history.delete(id: entry.id)
                                        await reload()
                                    }
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task(id: connectionID) { await reload() }
        .onChange(of: preferences.historyDisplayLimit) { _, _ in
            Task { await reload() }
        }
    }

    private var filteredEntries: [HistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.sql.localizedCaseInsensitiveContains(query) }
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedEntryIDs.contains(id) {
            expandedEntryIDs.remove(id)
        } else {
            expandedEntryIDs.insert(id)
        }
    }

    private func entryRow(_ entry: HistoryEntry) -> some View {
        let expanded = expandedEntryIDs.contains(entry.id)
        return VStack(alignment: .leading, spacing: 3) {
            Text(expanded ? entry.sql : entry.sql.singleLinePreview(limit: 80))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(expanded ? nil : 1)
                .truncationMode(.tail)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                Text(entry.executedAt, format: .relative(presentation: .numeric))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("\(entry.durationMs) ms")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let rowsAffected = entry.rowsAffected {
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(rowsAffected) row\(rowsAffected == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if entry.error != nil {
                    Spacer(minLength: 4)
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .imageScale(.small)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityLabel(entry.sql.singleLinePreview(limit: 120))
        .accessibilityHint("Single-click to expand, double-click to load into editor")
    }

    private func reload() async {
        do {
            entries = try await history.entries(
                forConnection: connectionID,
                limit: preferences.historyDisplayLimit
            )
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }
}

private extension String {
    /// Collapse to a single trimmed line for compact display, capped at `limit` chars.
    func singleLinePreview(limit: Int) -> String {
        let collapsed = self
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if collapsed.count <= limit { return collapsed }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<endIndex]) + "…"
    }
}
