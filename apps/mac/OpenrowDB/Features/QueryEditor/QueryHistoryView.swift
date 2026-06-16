// QueryHistoryView.swift
import OpenrowDBCore
import SwiftUI

/// Trailing inspector listing past queries for this connection, newest first.
/// Clicking an entry loads its SQL into the editor via the `onSelect` callback.
struct QueryHistoryView: View {
    @Environment(QueryHistoryStore.self) private var history
    let connectionID: UUID
    let onSelect: (String) -> Void

    @State private var entries: [HistoryEntry] = []
    @State private var loadError: String?

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

            if let loadError {
                ContentUnavailableView("History unavailable", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if entries.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "tray", description: Text("Run a query to populate this list."))
            } else {
                List {
                    ForEach(entries) { entry in
                        entryRow(entry)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(entry.sql) }
                            .contextMenu {
                                Button("Load into editor") { onSelect(entry.sql) }
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
    }

    private func entryRow(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.sql.singleLinePreview(limit: 80))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
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
    }

    private func reload() async {
        do {
            entries = try await history.entries(forConnection: connectionID, limit: 200)
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
