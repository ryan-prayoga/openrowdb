// ConnectionsSidebar.swift
import AppKit
import OpenrowDBCore
import SwiftUI

/// Sidebar: a filter field on top, then a tree of saved connections —
/// connection → databases → (schemas) → tables → columns. The tree is
/// flattened into individual `List` rows so each line is its own
/// `NSTableView` row: that gives every row its own context menu (no menu
/// leaking between siblings) and a clean per-row press highlight.
struct ConnectionsSidebar: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(WorkspaceTabsState.self) private var tabs
    @Environment(RefreshCoordinator.self) private var refreshCoordinator
    @Binding var selection: UUID?
    @Binding var showingNewConnection: Bool
    @Binding var editingConnection: Connection?

    @State private var pendingDelete: Connection?
    @State private var search = ""

    @State private var connExpanded: Set<UUID> = []
    @State private var connDatabases: [UUID: [String]] = [:]
    @State private var connLoading: Set<UUID> = []
    @State private var connError: [UUID: String] = [:]

    @State private var dbExpanded: Set<DBKey> = []
    @State private var dbTables: [DBKey: [TableRef]] = [:]
    @State private var dbCounts: [DBKey: [TableRef.ID: RowCount]] = [:]
    @State private var dbColumns: [DBKey: [TableRef.ID: [ColumnInfo]]] = [:]
    @State private var dbExpandedCols: [DBKey: Set<TableRef.ID>] = [:]
    @State private var dbLoading: Set<DBKey> = []
    @State private var dbError: [DBKey: String] = [:]

    @State private var pendingDropTable: TableRef?
    @State private var pendingDropKey: DBKey?
    @State private var pendingTruncateTable: TableRef?
    @State private var pendingTruncateKey: DBKey?
    @State private var renamingTable: TableRef?
    @State private var renamingKey: DBKey?
    @State private var renameText = ""
    @State private var pendingDropDB: DropDBTarget?
    @State private var creatingDatabaseConn: Connection?
    @State private var newDatabaseName = ""
    @State private var ddlError: String?

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            list
        }
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible, presenting: pendingDelete
        ) { conn in
            Button("Delete", role: .destructive) { Task { try? await manager.remove(conn) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the saved connection and its stored password. This can't be undone.")
        }
        .confirmationDialog(
            "Drop \u{201C}\(pendingDropTable?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDropTable != nil }, set: { if !$0 { pendingDropTable = nil } }),
            titleVisibility: .visible, presenting: pendingDropTable
        ) { table in
            Button("Drop Table", role: .destructive) {
                if let key = pendingDropKey { doDropTable(table, key: key) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes the table and all its rows. This can't be undone.")
        }
        .confirmationDialog(
            "Truncate \u{201C}\(pendingTruncateTable?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingTruncateTable != nil }, set: { if !$0 { pendingTruncateTable = nil } }),
            titleVisibility: .visible, presenting: pendingTruncateTable
        ) { table in
            Button("Truncate Table", role: .destructive) {
                if let key = pendingTruncateKey { doTruncate(table, key: key) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes every row but keeps the table. This can't be undone.")
        }
        .alert(
            "Rename \u{201C}\(renamingTable?.name ?? "")\u{201D}",
            isPresented: Binding(get: { renamingTable != nil }, set: { if !$0 { renamingTable = nil } })
        ) {
            TextField("New name", text: $renameText)
            Button("Rename") { commitRename() }
            Button("Cancel", role: .cancel) { renamingTable = nil }
        } message: {
            Text("Enter a new name for the table.")
        }
        .confirmationDialog(
            "Drop database \u{201C}\(pendingDropDB?.database ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDropDB != nil }, set: { if !$0 { pendingDropDB = nil } }),
            titleVisibility: .visible, presenting: pendingDropDB
        ) { target in
            Button("Drop Database", role: .destructive) { doDropDatabase(target) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This permanently deletes the database and everything in it. This can't be undone.")
        }
        .alert(
            "New Database",
            isPresented: Binding(get: { creatingDatabaseConn != nil }, set: { if !$0 { creatingDatabaseConn = nil } })
        ) {
            TextField("Database name", text: $newDatabaseName)
            Button("Create") { commitCreateDatabase() }
            Button("Cancel", role: .cancel) { creatingDatabaseConn = nil }
        } message: {
            Text("Enter a name for the new database.")
        }
        .alert("Operation failed",
               isPresented: Binding(get: { ddlError != nil }, set: { if !$0 { ddlError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(ddlError ?? "") }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).imageScale(.small)
            TextField("Filter tables & columns", text: $search).textFieldStyle(.plain)
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

    // MARK: - List

    private var list: some View {
        List {
            Section {
                if manager.connections.isEmpty {
                    Text("No connections yet").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(rows) { row in
                        rowView(row)
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                            .listRowSeparator(.hidden)
                    }
                }
            } header: {
                HStack {
                    Text("Connections")
                    Spacer()
                    Button { showingNewConnection = true } label: { Image(systemName: "plus") }
                        .buttonStyle(.glass).controlSize(.small).help("New Connection")
                }
            }
        }
        .transaction { $0.disablesAnimations = true }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 18)
    }

    // MARK: - Flattened tree

    private enum Row: Identifiable {
        case connection(Connection)
        case connLoading(UUID)
        case connError(UUID, String)
        case database(DBKey, Connection)
        case dbLoading(DBKey)
        case dbError(DBKey, String)
        case dbEmpty(DBKey, searching: Bool)
        case schema(DBKey, String)
        case table(DBKey, Connection, TableRef, Int)
        case column(DBKey, TableRef, ColumnInfo, Int)

        var id: String {
            switch self {
            case .connection(let c): "c:\(c.id)"
            case .connLoading(let id): "cl:\(id)"
            case .connError(let id, _): "ce:\(id)"
            case .database(let k, _): "d:\(k.connectionID):\(k.database)"
            case .dbLoading(let k): "dl:\(k.connectionID):\(k.database)"
            case .dbError(let k, _): "de:\(k.connectionID):\(k.database)"
            case .dbEmpty(let k, _): "dm:\(k.connectionID):\(k.database)"
            case .schema(let k, let s): "s:\(k.connectionID):\(k.database):\(s)"
            case .table(let k, _, let t, _): "t:\(k.connectionID):\(k.database):\(t.id)"
            case .column(let k, let t, let col, _): "col:\(k.connectionID):\(k.database):\(t.id):\(col.name)"
            }
        }
    }

    private var rows: [Row] {
        var out: [Row] = []
        for conn in manager.connections {
            out.append(.connection(conn))
            guard connExpanded.contains(conn.id) else { continue }
            let dbs = connDatabases[conn.id] ?? []
            if connLoading.contains(conn.id) && dbs.isEmpty { out.append(.connLoading(conn.id)); continue }
            if let err = connError[conn.id] { out.append(.connError(conn.id, err)); continue }
            for database in dbs {
                let key = DBKey(connectionID: conn.id, database: database)
                out.append(.database(key, conn))
                guard dbExpanded.contains(key) else { continue }
                if dbLoading.contains(key) && (dbTables[key] ?? []).isEmpty { out.append(.dbLoading(key)); continue }
                if let err = dbError[key] { out.append(.dbError(key, err)); continue }
                let visible = visibleTables(key: key)
                if visible.isEmpty { out.append(.dbEmpty(key, searching: !search.isEmpty)); continue }
                let schemas = uniqueSchemas(from: visible)
                if schemas.count <= 1 {
                    for table in visible { appendTable(&out, table, key: key, conn: conn, level: 2) }
                } else {
                    for schema in schemas {
                        out.append(.schema(key, schema))
                        for table in visible where table.schema == schema {
                            appendTable(&out, table, key: key, conn: conn, level: 3)
                        }
                    }
                }
            }
        }
        return out
    }

    private func appendTable(_ out: inout [Row], _ table: TableRef, key: DBKey, conn: Connection, level: Int) {
        out.append(.table(key, conn, table, level))
        guard showColumns(for: table, key: key) else { return }
        for column in matchingColumns(of: table, key: key) {
            out.append(.column(key, table, column, level + 2))
        }
    }

    // MARK: - Row views

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row {
        case .connection(let conn):
            connectionRow(conn)
        case .connLoading:
            TreeRow(level: 1, extraLeading: 20) {
                ProgressView().controlSize(.small)
                Text("Loading databases…").foregroundStyle(.secondary).font(.callout)
            }
        case .connError(_, let message):
            TreeRow(level: 1, extraLeading: 20) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).foregroundStyle(.secondary).font(.callout).lineLimit(2)
            }
        case .database(let key, let conn):
            databaseRow(key: key, conn: conn)
        case .dbLoading:
            TreeRow(level: 2, extraLeading: 20) {
                ProgressView().controlSize(.small)
                Text("Loading…").foregroundStyle(.secondary).font(.callout)
            }
        case .dbError(_, let message):
            TreeRow(level: 2, extraLeading: 20) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                Text(message).foregroundStyle(.secondary).font(.callout).lineLimit(2)
            }
        case .dbEmpty(_, let searching):
            TreeRow(level: 2, extraLeading: 20) {
                Text(searching ? "No matches" : "No tables").foregroundStyle(.secondary).font(.callout)
            }
        case .schema(_, let schema):
            TreeRow(level: 2, extraLeading: 20) {
                Image(systemName: "folder").foregroundStyle(.secondary).imageScale(.small)
                Text(schema).font(.callout).foregroundStyle(.secondary)
            }
        case .table(let key, let conn, let table, let level):
            tableRow(table, key: key, conn: conn, level: level)
        case .column(let key, let table, let column, let level):
            columnRow(column, of: table, key: key, level: level)
        }
    }

    @ViewBuilder
    private func connectionRow(_ conn: Connection) -> some View {
        let status = manager.status[conn.id] ?? .disconnected
        ConnHeaderRow(
            connection: conn,
            status: status,
            isSelected: selection == conn.id,
            onSingleTap: { if selection != conn.id { selection = conn.id } },
            onDoubleTap: {
                selection = conn.id
                if connExpanded.contains(conn.id) {
                    connExpanded.remove(conn.id)
                } else {
                    connExpanded.insert(conn.id)
                    Task { await connectAndLoad(conn) }
                }
            },
            onConnect: {
                connExpanded.insert(conn.id)
                Task { await connectAndLoad(conn) }
            },
            onDisconnect: { Task { await manager.disconnect(conn.id) } },
            onRefresh: { refreshCoordinator.refresh(connectionID: conn.id) },
            onEdit: { editingConnection = conn },
            onDelete: { pendingDelete = conn },
            newTableDatabases: connDatabases[conn.id] ?? [],
            canCreateTable: !manager.isReadOnly(conn.id),
            onNewTable: { db in newTable(conn: conn, database: db) },
            onNewTableUnloaded: {
                connExpanded.insert(conn.id)
                Task {
                    await connectAndLoad(conn)
                    if let db = (connDatabases[conn.id] ?? []).first {
                        newTable(conn: conn, database: db)
                    }
                }
            },
            onNewDatabase: {
                newDatabaseName = ""
                creatingDatabaseConn = conn
            }
        )
        .onChange(of: refreshCoordinator.signal(for: conn.id)) { _, _ in
            guard connExpanded.contains(conn.id), manager.status[conn.id] == .connected else { return }
            Task {
                await loadDatabases(for: conn)
                for database in connDatabases[conn.id] ?? [] {
                    let key = DBKey(connectionID: conn.id, database: database)
                    if dbExpanded.contains(key) { await refreshDB(key: key, conn: conn) }
                }
            }
        }
    }

    @ViewBuilder
    private func databaseRow(key: DBKey, conn: Connection) -> some View {
        let isReadOnly = manager.isReadOnly(conn.id)
        Button(action: { toggleDB(key: key, conn: conn) }) {
            TreeRow(level: 1, extraLeading: 20) {
                ChevronGlyph(expanded: dbExpanded.contains(key))
                Image(systemName: "cylinder").foregroundStyle(.secondary).imageScale(.small)
                Text(key.database)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(SidebarRowStyle())
        .contextMenu {
            if !isReadOnly {
                Button("New Table…") { newTable(conn: conn, database: key.database) }
            }
            Button("Refresh") {
                dbExpanded.insert(key)
                Task { await refreshDB(key: key, conn: conn) }
            }
            Divider()
            Button("Export Database as SQL…") { exportDatabase(key: key, conn: conn) }
            Button("Copy Name") { copy(key.database) }
            if !isReadOnly {
                Divider()
                Button("Drop Database…", role: .destructive) {
                    pendingDropDB = DropDBTarget(connID: conn.id, database: key.database)
                }
            }
        }
    }

    @ViewBuilder
    private func tableRow(_ table: TableRef, key: DBKey, conn: Connection, level: Int) -> some View {
        let expandedCols = dbExpandedCols[key] ?? []
        let allSchm = allSchemas(key: key)
        let defSchema = defaultSchema(key: key, dialect: conn.driver.dialect)
        let isReadOnly = manager.isReadOnly(conn.id)
        Button {
            selection = conn.id
            tabs.openTableTab(table, for: conn.id)
        } label: {
            TreeRow(level: level, extraLeading: 20) {
                ChevronGlyph(expanded: expandedCols.contains(table.id))
                    .onTapGesture { toggleColumns(table, key: key) }
                Image(systemName: table.kind == .view ? "eye" : "tablecells")
                    .foregroundStyle(.secondary).imageScale(.small)
                Text(table.name).lineLimit(1)
                Spacer(minLength: 0)
                if let count = dbCounts[key]?[table.id] {
                    Text("\(count.isEstimate ? "~" : "")\(count.value)")
                        .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
        .buttonStyle(SidebarRowStyle())
        .help("\(table.schema).\(table.name)\(table.kind == .view ? " (view)" : "")")
        .contextMenu {
            tableMenu(table, key: key, conn: conn, allSchm: allSchm, defSchema: defSchema, isReadOnly: isReadOnly)
        }
    }

    @ViewBuilder
    private func tableMenu(
        _ table: TableRef, key: DBKey, conn: Connection,
        allSchm: [String], defSchema: String, isReadOnly: Bool
    ) -> some View {
        Button("Open in New Tab") {
            selection = conn.id
            tabs.openTableTab(table, for: conn.id)
        }
        Button("Refresh") { refreshTable(table, key: key) }
        if table.kind == .table, !isReadOnly {
            Divider()
            Button("Edit Structure…") {
                selection = conn.id
                tabs.openStructureTab(
                    for: conn.id, dialect: conn.driver.dialect,
                    database: key.database, schemas: allSchm, defaultSchema: defSchema,
                    existingTable: table,
                    onSaved: { saved in Task { await reloadDB(key: key, conn: conn, select: saved) } }
                )
            }
            Button("Rename Table…") { startRename(table, key: key) }
        }
        Divider()
        Button("Copy Name") { copy(table.name) }
        Button("Copy Qualified Name") { copy("\(table.schema).\(table.name)") }
        if table.kind == .table {
            Button("Copy CREATE Statement") { copyCreateStatement(table, key: key, conn: conn) }
            Button("Export as SQL…") { exportTable(table, key: key, conn: conn) }
        }
        if table.kind == .table, !isReadOnly {
            Divider()
            Button("Truncate Table…", role: .destructive) {
                pendingTruncateTable = table
                pendingTruncateKey = key
            }
            Button("Drop Table…", role: .destructive) {
                pendingDropTable = table
                pendingDropKey = key
            }
        }
    }

    @ViewBuilder
    private func columnRow(_ column: ColumnInfo, of table: TableRef, key: DBKey, level: Int) -> some View {
        TreeRow(level: level, extraLeading: 20) {
            Image(systemName: columnIcon(for: column.type))
                .foregroundStyle(.tertiary).imageScale(.small).frame(width: 12)
            Text(column.name).font(.callout)
            Text(column.type).font(.caption).foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .help("\(table.name).\(column.name) · \(column.type)")
        .contextMenu {
            Button("Copy Name") { copy(column.name) }
            Button("Copy Qualified Name") { copy("\(table.name).\(column.name)") }
        }
    }

    // MARK: - Helpers

    private func visibleTables(key: DBKey) -> [TableRef] {
        let tables = dbTables[key] ?? []
        guard !search.isEmpty else { return tables }
        return tables.filter { t in
            t.name.localizedCaseInsensitiveContains(search) ||
            (dbColumns[key]?[t.id] ?? []).contains { $0.name.localizedCaseInsensitiveContains(search) }
        }
    }

    private func uniqueSchemas(from tables: [TableRef]) -> [String] {
        var seen: [String] = []
        for t in tables where !seen.contains(t.schema) { seen.append(t.schema) }
        return seen
    }

    private func allSchemas(key: DBKey) -> [String] { uniqueSchemas(from: dbTables[key] ?? []) }

    private func defaultSchema(key: DBKey, dialect: SQLDialect) -> String {
        if dialect == .mysql { return key.database }
        let s = allSchemas(key: key)
        return s.contains("public") ? "public" : (s.first ?? "public")
    }

    private func showColumns(for table: TableRef, key: DBKey) -> Bool {
        if dbExpandedCols[key]?.contains(table.id) == true { return true }
        guard !search.isEmpty, !table.name.localizedCaseInsensitiveContains(search) else { return false }
        return !matchingColumns(of: table, key: key).isEmpty
    }

    private func matchingColumns(of table: TableRef, key: DBKey) -> [ColumnInfo] {
        let all = dbColumns[key]?[table.id] ?? []
        guard !search.isEmpty, !table.name.localizedCaseInsensitiveContains(search) else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private func columnIcon(for type: String) -> String {
        let t = type.lowercased()
        if t.contains("int") { return "number" }
        if t.contains("bool") { return "checkbox.circle" }
        if t.contains("char") || t.contains("text") || t.contains("varchar") { return "text.quote" }
        if t.contains("date") || t.contains("time") { return "calendar" }
        if t.contains("json") { return "curlybraces" }
        if t.contains("uuid") { return "number.circle" }
        if t.contains("float") || t.contains("double") || t.contains("decimal") || t.contains("numeric") { return "number.circle" }
        if t.contains("blob") || t.contains("bytea") || t.contains("binary") { return "doc.richtext" }
        if t.contains("enum") { return "list.bullet" }
        return "circle.grid.2x2"
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: - Connection loading

    private func connectAndLoad(_ conn: Connection) async {
        let status = manager.status[conn.id] ?? .disconnected
        if status != .connected { await manager.connect(conn.id) }
        guard manager.status[conn.id] == .connected else {
            connError[conn.id] = "Not connected."
            return
        }
        await loadDatabases(for: conn)
    }

    private func loadDatabases(for conn: Connection) async {
        connLoading.insert(conn.id)
        connError.removeValue(forKey: conn.id)
        defer { connLoading.remove(conn.id) }
        do {
            connDatabases[conn.id] = try await manager.databases(on: conn.id)
        } catch {
            connError[conn.id] = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
        }
    }

    // MARK: - Database loading

    private func toggleDB(key: DBKey, conn: Connection) {
        if dbExpanded.contains(key) {
            dbExpanded.remove(key)
        } else {
            dbExpanded.insert(key)
            if (dbTables[key] ?? []).isEmpty { Task { await loadTables(key: key, conn: conn) } }
        }
    }

    private func loadTables(key: DBKey, conn: Connection) async {
        dbLoading.insert(key)
        dbError.removeValue(forKey: key)
        defer { dbLoading.remove(key) }
        do {
            dbTables[key] = try await manager.tables(on: key.connectionID, database: key.database)
            await loadCounts(key: key)
        } catch {
            dbError[key] = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
        }
    }

    private func loadCounts(key: DBKey) async {
        for table in dbTables[key] ?? [] {
            if let count = try? await manager.rowCount(of: table, on: key.connectionID) {
                dbCounts[key, default: [:]][table.id] = count
            }
        }
    }

    private func loadColumns(_ table: TableRef, key: DBKey) async {
        if let cols = try? await manager.columns(of: table, on: key.connectionID) {
            dbColumns[key, default: [:]][table.id] = cols
        }
    }

    private func toggleColumns(_ table: TableRef, key: DBKey) {
        if dbExpandedCols[key]?.contains(table.id) == true {
            dbExpandedCols[key]?.remove(table.id)
        } else {
            dbExpandedCols[key, default: []].insert(table.id)
            if dbColumns[key]?[table.id] == nil { Task { await loadColumns(table, key: key) } }
        }
    }

    private func refreshDB(key: DBKey, conn: Connection) async {
        await loadTables(key: key, conn: conn)
        for tableID in dbExpandedCols[key] ?? [] {
            guard let table = (dbTables[key] ?? []).first(where: { $0.id == tableID }) else { continue }
            await loadColumns(table, key: key)
        }
    }

    private func reloadDB(key: DBKey, conn: Connection, select table: TableRef) async {
        await loadTables(key: key, conn: conn)
        selection = conn.id
        tabs.openTableTab(table, for: conn.id)
    }

    // MARK: - DDL

    /// Open a blank structure tab for a new table in `database`. Used by both
    /// the database row and the connection row's context menus.
    private func newTable(conn: Connection, database: String) {
        selection = conn.id
        let key = DBKey(connectionID: conn.id, database: database)
        tabs.openStructureTab(
            for: conn.id, dialect: conn.driver.dialect,
            database: database,
            schemas: allSchemas(key: key),
            defaultSchema: defaultSchema(key: key, dialect: conn.driver.dialect),
            onSaved: { t in Task { await reloadDB(key: key, conn: conn, select: t) } }
        )
    }

    private func commitCreateDatabase() {
        guard let conn = creatingDatabaseConn else { return }
        let name = newDatabaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            if manager.status[conn.id] != .connected { await manager.connect(conn.id) }
            do {
                try await manager.createDatabase(name, on: conn.id)
                connExpanded.insert(conn.id)
                await loadDatabases(for: conn)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    private func doDropDatabase(_ target: DropDBTarget) {
        guard let conn = manager.connections.first(where: { $0.id == target.connID }) else { return }
        Task {
            do {
                try await manager.dropDatabase(target.database, on: target.connID)
                let key = DBKey(connectionID: target.connID, database: target.database)
                dbExpanded.remove(key)
                dbTables.removeValue(forKey: key)
                dbCounts.removeValue(forKey: key)
                dbColumns.removeValue(forKey: key)
                await loadDatabases(for: conn)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    private func doDropTable(_ table: TableRef, key: DBKey) {
        guard let conn = manager.connections.first(where: { $0.id == key.connectionID }) else { return }
        Task {
            do {
                try await manager.dropTable(table, on: key.connectionID)
                await loadTables(key: key, conn: conn)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    private func doTruncate(_ table: TableRef, key: DBKey) {
        guard let conn = manager.connections.first(where: { $0.id == key.connectionID }) else { return }
        let sql = "TRUNCATE TABLE \(conn.driver.dialect.qualifiedName(table))"
        Task {
            do {
                _ = try await manager.run(sql, on: key.connectionID, database: key.database)
                await loadCounts(key: key)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    private func startRename(_ table: TableRef, key: DBKey) {
        renameText = table.name
        renamingKey = key
        renamingTable = table
    }

    private func commitRename() {
        guard let table = renamingTable, let key = renamingKey,
              let conn = manager.connections.first(where: { $0.id == key.connectionID }) else { return }
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != table.name else { return }
        Task {
            do {
                try await manager.renameTable(table, on: key.connectionID, to: newName)
                await loadTables(key: key, conn: conn)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    /// Reload just one table's row count (and its columns, if already loaded).
    private func refreshTable(_ table: TableRef, key: DBKey) {
        Task {
            if let count = try? await manager.rowCount(of: table, on: key.connectionID) {
                dbCounts[key, default: [:]][table.id] = count
            }
            if dbColumns[key]?[table.id] != nil { await loadColumns(table, key: key) }
        }
    }

    private func copyCreateStatement(_ table: TableRef, key: DBKey, conn: Connection) {
        Task {
            do {
                let sql = try await DatabaseExporter.buildDump(
                    tables: [table], manager: manager,
                    connectionID: key.connectionID, dialect: conn.driver.dialect,
                    options: SQLDumpBuilder.Options(dropIfExists: false, createTable: true, includeData: false)
                )
                copy(sql.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    private func exportDatabase(key: DBKey, conn: Connection) {
        guard let url = SQLFileIO.chooseSaveURL(suggested: "\(key.database).sql") else { return }
        Task {
            do {
                var tables = dbTables[key] ?? []
                if tables.isEmpty {
                    tables = try await manager.tables(on: key.connectionID, database: key.database)
                }
                let sql = try await DatabaseExporter.buildDump(
                    tables: tables, manager: manager,
                    connectionID: key.connectionID, dialect: conn.driver.dialect,
                    options: SQLDumpBuilder.Options(dropIfExists: true, createTable: true, includeData: true)
                )
                try SQLFileIO.write(sql, to: url)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }

    private func exportTable(_ table: TableRef, key: DBKey, conn: Connection) {
        guard let url = SQLFileIO.chooseSaveURL(suggested: "\(table.name).sql") else { return }
        Task {
            do {
                let sql = try await DatabaseExporter.buildDump(
                    tables: [table], manager: manager,
                    connectionID: key.connectionID, dialect: conn.driver.dialect, options: .init()
                )
                try SQLFileIO.write(sql, to: url)
            } catch {
                ddlError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
            }
        }
    }
}

// MARK: - DB key

private struct DBKey: Hashable {
    let connectionID: UUID
    let database: String
}

private struct DropDBTarget {
    let connID: UUID
    let database: String
}

// MARK: - Connection header row

/// Connection rows need single-tap (select) vs double-tap (expand/connect),
/// so they use tap gestures rather than a `Button`. Press feedback comes from
/// a never-completing `LongPressGesture` that flips `pressing` on mouse-down
/// and resets on release — without consuming the taps.
private struct ConnHeaderRow: View {
    let connection: Connection
    let status: ConnectionManager.Status
    let isSelected: Bool
    let onSingleTap: () -> Void
    let onDoubleTap: () -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    let onRefresh: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Databases known for this connection (drives the "New Table" submenu).
    let newTableDatabases: [String]
    let canCreateTable: Bool
    let onNewTable: (String) -> Void
    /// No databases loaded yet — connect, load, then create in the first one.
    let onNewTableUnloaded: () -> Void
    let onNewDatabase: () -> Void

    @GestureState private var pressing = false

    var body: some View {
        HStack(spacing: 6) {
            StatusDot(status: status).frame(width: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .foregroundStyle(.primary)
                    .fontWeight(isSelected ? .medium : .regular)
                Text("\(connection.driver.rawValue) · \(connection.host)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(pressing ? Color.primary.opacity(0.12) : .clear)
        )
        .contentShape(.rect)
        .onTapGesture(count: 2) { onDoubleTap() }
        .simultaneousGesture(TapGesture(count: 1).onEnded { onSingleTap() })
        .simultaneousGesture(
            LongPressGesture(minimumDuration: .infinity)
                .updating($pressing) { _, state, _ in state = true }
        )
        .contextMenu {
            if canCreateTable {
                if newTableDatabases.count > 1 {
                    Menu("New Table") {
                        ForEach(newTableDatabases, id: \.self) { db in
                            Button(db) { onNewTable(db) }
                        }
                    }
                } else {
                    Button("New Table…") {
                        if let db = newTableDatabases.first { onNewTable(db) }
                        else { onNewTableUnloaded() }
                    }
                }
                Button("New Database…") { onNewDatabase() }
                Divider()
            }
            if status == .connected {
                Button("Disconnect") { onDisconnect() }
                Button("Refresh") { onRefresh() }
            } else {
                Button("Connect") { onConnect() }.disabled(status == .connecting)
            }
            Button("Edit…") { onEdit() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }
}

// MARK: - Shared row chrome

/// Click highlight for rows driven by a `Button` (databases, tables). Shows a
/// subtle fill only while the mouse is held down — a press effect, not a hover.
private struct SidebarRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : .clear)
            )
            .contentShape(.rect)
    }
}

private struct TreeRow<Content: View>: View {
    let level: Int
    var extraLeading: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .padding(.leading, CGFloat(level) * 8 + 4 + extraLeading)
            .padding(.trailing, 4)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
