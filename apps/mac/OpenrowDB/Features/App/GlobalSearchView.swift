// GlobalSearchView.swift
import OpenrowDBCore
import SwiftUI

/// Command palette (⌘K) — search connections, tables, open tabs, and query history.
struct GlobalSearchView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(ConnectionManager.self) private var manager
  @Environment(QueryHistoryStore.self) private var history
  @Environment(WorkspaceTabsState.self) private var tabs
  @Environment(GlobalSearchCoordinator.self) private var coordinator

  @State private var query = ""
  @State private var results: [GlobalSearchResult] = []
  @State private var loadingTables = false
  @State private var searchGeneration: UInt64 = 0
  @FocusState private var queryFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      resultsList
    }
    .frame(width: 560, height: 420)
    .onAppear {
      queryFocused = true
      refreshResults()
    }
    .onChange(of: query) { _, _ in
      scheduleSearch()
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Search connections, tables, tabs, history…", text: $query)
        .textFieldStyle(.plain)
        .focused($queryFocused)
      if loadingTables {
        ProgressView().controlSize(.small)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private var resultsList: some View {
    if trimmedQuery.isEmpty {
      PlaceholderView(
        title: "Search everything",
        subtitle: "Type to find connections, tables, open tabs, or past queries.",
        systemImage: "command"
      )
    } else if results.isEmpty && !loadingTables {
      PlaceholderView(
        title: "No matches",
        subtitle: "Try a connection name, table name, or SQL keyword.",
        systemImage: "magnifyingglass"
      )
    } else {
      List(results) { result in
        Button {
          select(result)
        } label: {
          resultRow(result)
        }
        .buttonStyle(.plain)
      }
      .listStyle(.plain)
    }
  }

  private func resultRow(_ result: GlobalSearchResult) -> some View {
    HStack(spacing: 10) {
      Image(systemName: result.icon)
        .foregroundStyle(result.tint)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(result.title)
          .font(.callout)
          .lineLimit(1)
        if let subtitle = result.subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer()
      Text(result.badge)
        .font(.caption2)
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 2)
  }

  private var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func scheduleSearch() {
    searchGeneration += 1
    let generation = searchGeneration
    Task {
      try? await Task.sleep(for: .milliseconds(200))
      guard generation == searchGeneration else { return }
      await performSearch()
    }
  }

  @MainActor
  private func performSearch() async {
    let generation = searchGeneration
    let needle = trimmedQuery.lowercased()
    guard !needle.isEmpty else {
      results = []
      loadingTables = false
      return
    }

    var found: [GlobalSearchResult] = []

    for conn in manager.connections where matchesConnection(conn, needle: needle) {
      found.append(.connection(conn))
    }

    for conn in manager.connections {
      for tab in tabs.tabs(for: conn.id) {
        if let match = openTabResult(conn: conn, tab: tab, needle: needle) {
          found.append(match)
        }
      }
    }

    if let entries = try? await history.allEntries(limit: 300) {
      for entry in entries {
        guard let conn = manager.connections.first(where: { $0.id == entry.connectionID }) else { continue }
        if entry.sql.localizedCaseInsensitiveContains(needle) {
          found.append(.history(conn, entry))
        }
      }
    }

    results = Array(found.prefix(40))
    loadingTables = true
    var tableResults: [GlobalSearchResult] = []
    for conn in manager.connections where manager.status[conn.id] == .connected {
      if let tables = try? await manager.tables(on: conn.id) {
        for table in tables where table.name.localizedCaseInsensitiveContains(needle) {
          tableResults.append(.table(conn, table))
        }
      }
    }
    loadingTables = false
    guard generation == searchGeneration else { return }
    results = Array((found + tableResults).prefix(50))
  }

  private func refreshResults() {
    Task { await performSearch() }
  }

  private func matchesConnection(_ conn: Connection, needle: String) -> Bool {
    conn.name.localizedCaseInsensitiveContains(needle)
      || conn.host.localizedCaseInsensitiveContains(needle)
      || conn.database.localizedCaseInsensitiveContains(needle)
  }

  private func openTabResult(conn: Connection, tab: WorkspaceTab, needle: String) -> GlobalSearchResult? {
    switch tab {
    case .query(let id):
      let title = tabs.queryTabTitle(for: id) ?? "Query"
      guard title.localizedCaseInsensitiveContains(needle) else { return nil }
      return .openTab(conn, tab, title: title)
    case .table(let ref):
      guard ref.name.localizedCaseInsensitiveContains(needle) else { return nil }
      return .openTab(conn, tab, title: ref.name)
    case .structure:
      guard "structure".localizedCaseInsensitiveContains(needle) else { return nil }
      return .openTab(conn, tab, title: "Structure")
    }
  }

  private func select(_ result: GlobalSearchResult) {
    dismiss()
    switch result {
    case .connection(let conn):
      coordinator.onSelectConnection?(conn.id)
    case .table(let conn, let table):
      coordinator.onSelectConnection?(conn.id)
      coordinator.onOpenTable?(conn.id, table)
    case .history(let conn, let entry):
      coordinator.onSelectConnection?(conn.id)
      coordinator.onLoadHistoryQuery?(conn.id, entry.sql)
    case .openTab(let conn, let tab, _):
      coordinator.onSelectConnection?(conn.id)
      coordinator.onSelectTab?(conn.id, tab)
    }
  }
}

// MARK: - Result model

private enum GlobalSearchResult: Identifiable {
  case connection(Connection)
  case table(Connection, TableRef)
  case history(Connection, HistoryEntry)
  case openTab(Connection, WorkspaceTab, title: String)

  var id: String {
    switch self {
    case .connection(let conn): return "conn:\(conn.id)"
    case .table(let conn, let table): return "table:\(conn.id):\(table.id)"
    case .history(_, let entry): return "history:\(entry.id)"
    case .openTab(let conn, let tab, _): return "tab:\(conn.id):\(tab.id)"
    }
  }

  var title: String {
    switch self {
    case .connection(let conn): return conn.name
    case .table(_, let table): return table.name
    case .history(_, let entry): return entry.sqlPreview
    case .openTab(_, _, let title): return title
    }
  }

  var subtitle: String? {
    switch self {
    case .connection(let conn): return "\(conn.driver.displayName) · \(conn.host)"
    case .table(let conn, let table): return "\(conn.name) · \(table.database)"
    case .history(let conn, let entry):
      return "\(conn.name) · \(entry.executedAt.formatted(date: .abbreviated, time: .shortened))"
    case .openTab(let conn, _, _): return conn.name
    }
  }

  var badge: String {
    switch self {
    case .connection: return "Connection"
    case .table: return "Table"
    case .history: return "History"
    case .openTab: return "Open Tab"
    }
  }

  var icon: String {
    switch self {
    case .connection(let conn): return conn.driver.systemImage
    case .table(_, let table): return table.kind == .view ? "eye" : "tablecells"
    case .history: return "clock.arrow.circlepath"
    case .openTab(_, let tab, _):
      switch tab {
      case .query: return "terminal"
      case .table(let ref): return ref.kind == .view ? "eye" : "tablecells"
      case .structure: return "tablecells.badge.ellipsis"
      }
    }
  }

  var tint: Color {
    switch self {
    case .connection, .table, .openTab: return .accentColor
    case .history: return .secondary
    }
  }
}

private extension HistoryEntry {
  var sqlPreview: String {
    let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 72 { return trimmed }
    return String(trimmed.prefix(72)) + "…"
  }
}