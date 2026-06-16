// QuerySnippetsView.swift
import OpenrowDBCore
import SwiftUI

/// Trailing panel listing saved SQL snippets for this connection.
struct QuerySnippetsView: View {
    @Environment(QuerySnippetStore.self) private var snippets
    let connectionID: UUID
    let currentSQL: () -> String
    let onSelect: (String) -> Void

    @State private var entries: [SnippetEntry] = []
    @State private var loadError: String?
    @State private var showingSave = false
    @State private var saveTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .sheet(isPresented: $showingSave) {
            saveSheet
        }
        .task(id: connectionID) { await reload() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label("Snippets", systemImage: "bookmark")
                .font(.headline)
            Spacer()
            Button {
                saveTitle = ""
                showingSave = true
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Save current SQL as snippet")
            .disabled(currentSQL().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button { Task { await reload() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var content: some View {
        if let loadError {
            PlaceholderView(
                title: "Snippets unavailable",
                subtitle: loadError,
                systemImage: "exclamationmark.triangle",
                variant: .error
            )
        } else if entries.isEmpty {
            PlaceholderView(
                title: "No snippets yet",
                subtitle: "Save a query with the + button.",
                systemImage: "bookmark"
            )
        } else {
            List {
                ForEach(entries) { entry in
                    snippetRow(entry)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(entry.sql) }
                        .contextMenu {
                            Button("Load into editor") { onSelect(entry.sql) }
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? await snippets.delete(id: entry.id)
                                    await reload()
                                }
                            }
                        }
                }
            }
            .listStyle(.plain)
        }
    }

    private func snippetRow(_ entry: SnippetEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.title)
                .font(.callout)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(entry.sql.singleLinePreview(limit: 72))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private var saveSheet: some View {
        VStack(spacing: 16) {
            Text("Save Snippet")
                .font(.headline)
            TextField("Title", text: $saveTitle)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel", role: .cancel) { showingSave = false }
                    .buttonStyle(.glass)
                Button("Save") {
                    Task {
                        let sql = currentSQL()
                        _ = try? await snippets.upsert(connectionID: connectionID, title: saveTitle, sql: sql)
                        showingSave = false
                        await reload()
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(currentSQL().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func reload() async {
        do {
            entries = try await snippets.entries(forConnection: connectionID)
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }
}

private extension String {
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