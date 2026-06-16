// ConnectionsSidebar.swift
import AppKit
import OpenrowDBCore
import SwiftUI

/// Sidebar: a filter field on top, then a lazy tree of saved connections —
/// connection → databases → (schemas) → tables → columns. This is the app's
/// primary table navigator; double-clicking (or single-clicking) a table opens
/// it as a workspace tab. Table DDL (new / edit / export / drop) lives here too.
struct ConnectionsSidebar: View {
    @Environment(ConnectionManager.self) private var manager
    @Binding var selection: UUID?
    @Binding var showingNewConnection: Bool
    @Binding var editingConnection: Connection?

    @State private var pendingDelete: Connection?
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
        }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { connection in
            Button("Delete", role: .destructive) {
                Task { try? await manager.remove(connection) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the saved connection and its stored password. This can't be undone.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).imageScale(.small)
            TextField("Filter tables & columns", text: $search)
                .textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var list: some View {
        // No List(selection:) — each ConnectionNode is a single List row (header
        // + its database subtree), so the built-in highlight would paint the
        // whole subtree blue. Selection is driven by tap and the connection
        // header highlights itself.
        List {
            Section {
                if manager.connections.isEmpty {
                    Text("No connections yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(manager.connections) { connection in
                        ConnectionNode(
                            connection: connection,
                            search: search,
                            selection: $selection,
                            editingConnection: $editingConnection,
                            pendingDelete: $pendingDelete
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Connections")
                    Spacer()
                    Button {
                        showingNewConnection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("New Connection")
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Connection node

/// A connection row plus, when expanded and connected, its database children.
private struct ConnectionNode: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(RefreshCoordinator.self) private var refreshCoordinator
    let connection: Connection
    let search: String
    @Binding var selection: UUID?
    @Binding var editingConnection: Connection?
    @Binding var pendingDelete: Connection?

    @State private var expanded = false
    @State private var databases: [String] = []
    @State private var loading = false
    @State private var loadError: String?

    private var status: ConnectionManager.Status {
        manager.status[connection.id] ?? .disconnected
    }

    private var isSelected: Bool { selection == connection.id }

    var body: some View {
        Group {
            row
            if expanded {
                children
            }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            DisclosureChevron(expanded: expanded, tint: .secondary) { toggle() }
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .foregroundStyle(.primary)
                    .fontWeight(isSelected ? .medium : .regular)
                Text("\(connection.driver.rawValue) · \(connection.host)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(0.07))
            }
        }
        .contentShape(.rect)
        .onTapGesture(count: 2) {
            selection = connection.id
            guard status != .connecting, status != .connected else { return }
            Task { await connectAndExpand() }
        }
        .simultaneousGesture(TapGesture(count: 1).onEnded {
            if selection != connection.id { selection = connection.id }
        })
        .contextMenu {
            if status == .connected {
                Button("Disconnect") { Task { await manager.disconnect(connection.id) } }
                Button("Refresh") { refreshCoordinator.refresh(connectionID: connection.id) }
            } else {
                Button("Connect") { Task { await connectAndExpand() } }
                    .disabled(status == .connecting)
            }
            Button("Edit…") { editingConnection = connection }
            Divider()
            Button("Delete", role: .destructive) { pendingDelete = connection }
        }
        .onChange(of: refreshCoordinator.signal(for: connection.id)) { _, _ in
            guard status == .connected, expanded else { return }
            Task { await loadDatabases() }
        }
    }

    @ViewBuilder
    private var children: some View {
        if loading && databases.isEmpty {
            TreeRow(level: 1) {
                ProgressView().controlSize(.small)
                Text("Loading databases…").foregroundStyle(.secondary).font(.callout)
            }
        } else if let loadError {
            TreeRow(level: 1) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(loadError).foregroundStyle(.secondary).font(.callout).lineLimit(2)
            }
        } else {
            ForEach(databases, id: \.self) { database in
                DatabaseNode(
                    connectionID: connection.id,
                    database: database,
                    dialect: connection.driver.dialect,
                    defaultDatabase: connection.database,
                    search: search,
                    onSelectConnection: { selection = connection.id }
                )
            }
        }
    }

    private func toggle() {
        expanded.toggle()
        guard expanded else { return }
        Task { await connectAndLoad() }
    }

    private func connectAndExpand() async {
        await connectAndLoad()
        expanded = true
    }

    private func connectAndLoad() async {
        if status != .connected {
            await manager.connect(connection.id)
        }
        guard manager.status[connection.id] == .connected else {
            loadError = "Not connected."
            return
        }
        await loadDatabases()
    }

    private func loadDatabases() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            databases = try await manager.databases(on: connection.id)
        } catch {
            loadError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
        }
    }
}

// MARK: - Database node

/// A database row plus, when expanded, its tables (grouped by schema when the
/// database exposes more than one). Owns table DDL for this database: new table,
/// edit structure, export, drop. Tables expand to show columns (lazy-loaded),
/// which also feeds column search.
private struct DatabaseNode: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(WorkspaceTabsState.self) private var tabs
    @Environment(RefreshCoordinator.self) private var refreshCoordinator
    let connectionID: UUID
    let database: String
    let dialect: SQLDialect
    let defaultDatabase: String
    let search: String
    let onSelectConnection: () -> Void

    @State private var expanded = false
    @State private var tables: [TableRef] = []
    @State private var counts: [TableRef.ID: RowCount] = [:]
    @State private var columnsByTable: [TableRef.ID: [ColumnInfo]] = [:]
    @State private var expandedTables: Set<TableRef.ID> = []
    @State private var loading = false
    @State private var loadError: String?

    @State private var pendingDropTable: TableRef?
    @State private var ddlError: String?

    private var searching: Bool { !search.isEmpty }

    private var schemas: [String] {
        var seen: [String] = []
        for table in visibleTables where !seen.contains(table.schema) { seen.append(table.schema) }
        return seen
    }

    /// Tables matching the search (by name, or by any loaded column name).
    private var visibleTables: [TableRef] {
        guard searching else { return tables }
        return tables.filter { table in
            matches(table.name) || (columnsByTable[table.id] ?? []).contains { matches($0.name) }
        }
    }

    private var allSchemas: [String] {
        var seen: [String] = []
        for table in tables where !seen.contains(table.schema) { seen.append(table.schema) }
        return seen
    }

    private var defaultSchema: String {
        if dialect == .mysql { return database }
        if allSchemas.contains("public") { return "public" }
        return allSchemas.first ?? "public"
    }

    var body: some View {
        Group {
            Button(action: toggle) {
                TreeRow(level: 1) {
                    ChevronGlyph(expanded: expanded)
                    Image(systemName: "cylinder.split.1x2").foregroundStyle(.secondary).imageScale(.small)
                    Text(database)
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("New Table…") {
                    onSelectConnection()
                    tabs.openStructureTab(
                        for: connectionID,
                        dialect: dialect,
                        database: database,
                        schemas: allSchemas,
                        defaultSchema: defaultSchema,
                        onSaved: { table in Task { await reloadKeeping(select: table) } }
                    )
                }
            }

            if expanded { children }
        }
        .confirmationDialog(
            "Drop \u{201C}\(pendingDropTable?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDropTable != nil }, set: { if !$0 { pendingDropTable = nil } }),
            titleVisibility: .visible,
            presenting: pendingDropTable
        ) { table in
            Button("Drop Table", role: .destructive) { dropTable(table) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes the table and all its rows. This can't be undone.")
        }
        .alert("Operation failed", isPresented: Binding(get: { ddlError != nil }, set: { if !$0 { ddlError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ddlError ?? "")
        }
        .onChange(of: refreshCoordinator.signal(for: connectionID)) { _, _ in
            Task { await refreshExpandedContent() }
        }
    }

    @ViewBuilder
    private var children: some View {
        if loading && tables.isEmpty {
            TreeRow(level: 2) {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary).font(.callout)
            }
        } else if let loadError {
            TreeRow(level: 2) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(loadError).foregroundStyle(.secondary).font(.callout).lineLimit(2)
            }
        } else if visibleTables.isEmpty {
            TreeRow(level: 2) {
                Text(searching ? "No matches" : "No tables").foregroundStyle(.secondary).font(.callout)
            }
        } else if schemas.count <= 1 {
            ForEach(visibleTables) { table in tableNode(table, level: 2) }
        } else {
            ForEach(schemas, id: \.self) { schema in
                TreeRow(level: 2) {
                    Image(systemName: "folder").foregroundStyle(.secondary).imageScale(.small)
                    Text(schema).font(.callout).foregroundStyle(.secondary)
                }
                ForEach(visibleTables.filter { $0.schema == schema }) { table in tableNode(table, level: 3) }
            }
        }
    }

    // MARK: Table + column rows

    @ViewBuilder
    private func tableNode(_ table: TableRef, level: Int) -> some View {
        tableRow(table, level: level)
        if showColumns(for: table) {
            ForEach(matchingColumns(of: table)) { column in
                TreeRow(level: level + 1) {
                    Image(systemName: "tablecells.badge.ellipsis").foregroundStyle(.tertiary).imageScale(.small)
                    Text(column.name).font(.callout)
                    Text(column.type).font(.caption).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .help("\(table.name).\(column.name) · \(column.type)")
            }
        }
    }

    private func tableRow(_ table: TableRef, level: Int) -> some View {
        Button {
            onSelectConnection()
            tabs.openTableTab(table, for: connectionID)
        } label: {
            TreeRow(level: level) {
                ChevronGlyph(expanded: expandedTables.contains(table.id))
                    .onTapGesture { toggleColumns(table) }
                Image(systemName: table.kind == .view ? "eye" : "tablecells")
                    .foregroundStyle(.secondary).imageScale(.small)
                Text(table.name).lineLimit(1)
                Spacer(minLength: 0)
                if let count = counts[table.id] {
                    Text("\(count.isEstimate ? "~" : "")\(count.value)")
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("\(table.schema).\(table.name)\(table.kind == .view ? " (view)" : "")")
        .contextMenu {
            Button("Open in New Tab") {
                onSelectConnection()
                tabs.openTableTab(table, for: connectionID)
            }
            if table.kind == .table {
                Button("Edit Structure…") {
                    onSelectConnection()
                    tabs.openStructureTab(
                        for: connectionID,
                        dialect: dialect,
                        database: database,
                        schemas: allSchemas,
                        defaultSchema: defaultSchema,
                        existingTable: table,
                        onSaved: { saved in Task { await reloadKeeping(select: saved) } }
                    )
                }
                Button("Export as SQL…") { exportTable(table) }
            }
            Divider()
            Button("Copy Name") { copy(table.name) }
            Button("Copy Qualified Name") { copy("\(table.schema).\(table.name)") }
            if table.kind == .table {
                Divider()
                Button("Drop Table…", role: .destructive) { pendingDropTable = table }
            }
        }
    }

    private func showColumns(for table: TableRef) -> Bool {
        if expandedTables.contains(table.id) { return true }
        // While searching, auto-reveal columns of a table that matched only via
        // a column (not its own name) so the match is visible.
        return searching && !matches(table.name) && matchingColumns(of: table).isEmpty == false
    }

    private func matchingColumns(of table: TableRef) -> [ColumnInfo] {
        let all = columnsByTable[table.id] ?? []
        guard searching, !matches(table.name) else { return all }
        return all.filter { matches($0.name) }
    }

    // MARK: Toggling / loading

    private func toggle() {
        expanded.toggle()
        guard expanded, tables.isEmpty else { return }
        Task { await loadTables() }
    }

    private func toggleColumns(_ table: TableRef) {
        if expandedTables.contains(table.id) {
            expandedTables.remove(table.id)
        } else {
            expandedTables.insert(table.id)
            if columnsByTable[table.id] == nil { Task { await loadColumns(table) } }
        }
    }

    private func loadTables() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            tables = try await manager.tables(on: connectionID, database: database)
            await loadCounts()
        } catch {
            loadError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
        }
    }

    /// Hybrid counts: big tables use the instant estimate, small ones an exact
    /// COUNT — same policy the Browse pane used, so no large table is scanned.
    private func loadCounts() async {
        for table in tables {
            if let count = try? await manager.rowCount(of: table, on: connectionID) {
                counts[table.id] = count
            }
        }
    }

    private func loadColumns(_ table: TableRef) async {
        if let cols = try? await manager.columns(of: table, on: connectionID) {
            columnsByTable[table.id] = cols
        }
    }

    /// Reload tables + counts for an expanded database, and column metadata for
    /// any table whose column chevron is open.
    private func refreshExpandedContent() async {
        guard expanded else { return }
        await loadTables()
        for tableID in expandedTables {
            guard let table = tables.first(where: { $0.id == tableID }) else { continue }
            await loadColumns(table)
        }
    }

    private func reloadKeeping(select table: TableRef) async {
        await loadTables()
        onSelectConnection()
        tabs.openTableTab(table, for: connectionID)
    }

    // MARK: DDL actions

    private func dropTable(_ table: TableRef) {
        Task {
            do {
                try await manager.dropTable(table, on: connectionID)
                await loadTables()
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            }
        }
    }

    private func exportTable(_ table: TableRef) {
        guard let url = SQLFileIO.chooseSaveURL(suggested: "\(table.name).sql") else { return }
        Task {
            do {
                let sql = try await DatabaseExporter.buildDump(
                    tables: [table],
                    manager: manager,
                    connectionID: connectionID,
                    dialect: dialect,
                    options: .init()
                )
                try SQLFileIO.write(sql, to: url)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func matches(_ name: String) -> Bool {
        name.localizedCaseInsensitiveContains(search)
    }
}

// MARK: - Shared row chrome

/// An indented tree row. `level` controls leading inset so nesting reads
/// visually without relying on `DisclosureGroup`'s selection-hostile layout.
private struct TreeRow<Content: View>: View {
    let level: Int
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) { content }
            .padding(.leading, CGFloat(level) * 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A non-interactive expand/collapse chevron, for rows that are themselves a
/// Button (nesting a Button inside a Button double-fires the action). It still
/// takes taps via an attached `.onTapGesture` at the call site when needed.
private struct ChevronGlyph: View {
    let expanded: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .rotationEffect(.degrees(expanded ? 90 : 0))
            .foregroundStyle(.secondary)
            .imageScale(.small)
            .frame(width: 12)
            .contentShape(.rect)
            .animation(.easeInOut(duration: 0.15), value: expanded)
    }
}

/// A clickable expand/collapse chevron Button.
private struct DisclosureChevron: View {
    let expanded: Bool
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(tint)
                .imageScale(.small)
                .frame(width: 12)
        }
        .buttonStyle(.borderless)
        .animation(.easeInOut(duration: 0.15), value: expanded)
    }
}

private struct StatusDot: View {
    let status: ConnectionManager.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(label)
    }

    private var color: Color {
        switch status {
        case .disconnected: .secondary
        case .connecting: .yellow
        case .connected: .green
        case .failed: .red
        }
    }

    private var label: String {
        switch status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .failed(let message): "Failed: \(message)"
        }
    }
}
