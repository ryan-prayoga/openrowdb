// ConnectionManager.swift
import Foundation
import Observation

/// Orchestrates saved connections: persistence (`ConnectionStore`), secrets
/// (`SecretStore`), and live driver clients. Owns connection lifecycle + status.
///
/// `@MainActor` + `@Observable` so SwiftUI can bind directly. The driver factory is
/// injectable so the orchestration logic can be tested without a real database.
@MainActor
@Observable
public final class ConnectionManager {
    public enum Status: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    /// Builds a driver client for a connection + resolved password.
    public typealias ClientFactory = @Sendable (Connection, String?) -> any DatabaseClient

    public private(set) var connections: [Connection] = []
    public private(set) var status: [UUID: Status] = [:]

    private let store: ConnectionStore
    private let secrets: SecretStore
    private let makeClient: ClientFactory
    private let sshTunnels = SSHTunnelManager()

    /// Live clients keyed by (connection, database). A saved connection's
    /// primary client lives under its default database; Postgres opens an extra
    /// client per non-default database browsed (it can't switch DB on a live
    /// connection), while MySQL serves every database from the primary client.
    private struct ClientKey: Hashable {
        let connectionID: UUID
        let database: String
    }
    private var clients: [ClientKey: any DatabaseClient] = [:]

    public init(
        store: ConnectionStore,
        secrets: SecretStore,
        clientFactory: @escaping ClientFactory = { DatabaseClientFactory.make(for: $0, password: $1) }
    ) {
        self.store = store
        self.secrets = secrets
        self.makeClient = clientFactory
    }

    /// Load persisted connections into memory. Call once at startup.
    public func reload() throws {
        connections = try store.load()
        for connection in connections where status[connection.id] == nil {
            status[connection.id] = .disconnected
        }
    }

    /// Persist a new connection and its password.
    public func add(_ connection: Connection, password: String) throws {
        try secrets.set(password, for: connection.passwordKeychainKey)
        try store.upsert(connection)
        connections = try store.load()
        status[connection.id] = .disconnected
    }

    /// Store an arbitrary secret (e.g. SSH password) in the Keychain.
    public func storeSecret(_ value: String, for key: String) throws {
        try secrets.set(value, for: key)
    }

    /// Update metadata, and the password when a new one is supplied (nil = keep existing).
    public func update(_ connection: Connection, password: String?) throws {
        if let password {
            try secrets.set(password, for: connection.passwordKeychainKey)
        }
        try store.upsert(connection)
        connections = try store.load()
    }

    /// Disconnect, then delete the client, secret, and metadata.
    ///
    /// Secret removal is best-effort: a stale or inaccessible Keychain item (for
    /// example one created by an earlier ad-hoc-signed dev build, which the current
    /// build's signature can't delete) must never block removing the connection.
    public func remove(_ connection: Connection) async throws {
        await disconnect(connection.id)
        await sshTunnels.close(connectionID: connection.id)
        try? secrets.remove(connection.passwordKeychainKey)
        try store.remove(id: connection.id)
        connections = try store.load()
        status[connection.id] = nil
    }

    /// Open a live connection. Idempotent: re-running a connected id is a no-op.
    public func connect(_ id: UUID) async {
        guard let connection = connections.first(where: { $0.id == id }) else { return }
        if status[id] == .connected { return }

        status[id] = .connecting
        let password: String?
        do {
            password = try secrets.get(connection.passwordKeychainKey)
        } catch {
            status[id] = .failed("Keychain read failed: \(error)")
            return
        }

        do {
            let (effective, dbPassword) = try await resolvedEndpoint(for: connection, password: password)
            let client = makeClient(effective, dbPassword)
            do {
                try await client.connect()
                clients[ClientKey(connectionID: id, database: connection.database)] = client
                status[id] = .connected
            } catch {
                await client.close()
                await sshTunnels.close(connectionID: id)
                status[id] = .failed(Self.message(for: error))
            }
        } catch {
            await sshTunnels.close(connectionID: id)
            status[id] = .failed(Self.message(for: error))
        }
    }

    /// Try connecting with the given parameters without persisting anything.
    /// Returns `nil` on success, or a human-readable error message on failure.
    public func test(_ connection: Connection, password: String?) async -> String? {
        do {
            let (effective, dbPassword) = try await resolvedEndpoint(for: connection, password: password)
            let client = makeClient(effective, dbPassword)
            try await client.connect()
            await client.close()
            await sshTunnels.close(connectionID: connection.id)
            return nil
        } catch {
            await sshTunnels.close(connectionID: connection.id)
            return Self.message(for: error)
        }
    }

    /// Close and forget every live client for a connection (its primary client
    /// plus any per-database clients opened while browsing other catalogs).
    public func disconnect(_ id: UUID) async {
        let keys = clients.keys.filter { $0.connectionID == id }
        for key in keys {
            if let client = clients.removeValue(forKey: key) {
                await client.close()
            }
        }
        await sshTunnels.close(connectionID: id)
        if status[id] != nil {
            status[id] = .disconnected
        }
    }

    /// Whether the saved connection is flagged read-only.
    public func isReadOnly(_ id: UUID) -> Bool {
        connections.first(where: { $0.id == id })?.isReadOnly ?? false
    }

    /// Run SQL against an already-connected id, optionally targeting a specific
    /// database (nil = the connection's default database).
    public func run(_ sql: String, on id: UUID, database: String? = nil) async throws -> QueryResult {
        try assertWritableSQL(sql, on: id)
        return try await perform(id, database: database) { try await $0.query(sql) }
    }

    /// Run EXPLAIN on a single SQL statement.
    public func explain(_ sql: String, on id: UUID, database: String? = nil) async throws -> QueryResult {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DatabaseError.driver("Nothing to explain.") }
        return try await perform(id, database: database) { client in
            try await client.query(client.dialect.explainSQL(trimmed))
        }
    }

    /// List databases (catalogs) on an already-connected id.
    public func databases(on id: UUID) async throws -> [String] {
        try await perform(id) { try await $0.listDatabases() }
    }

    /// List user tables and views for an already-connected id, optionally in a
    /// specific database (nil = the connection's default database).
    public func tables(on id: UUID, database: String? = nil) async throws -> [TableRef] {
        let resolved = resolvedDatabase(id, database)
        return try await perform(id, database: resolved) { try await $0.listTables(in: resolved) }
    }

    /// A table's columns and their types for an already-connected id.
    public func columns(of table: TableRef, on id: UUID) async throws -> [ColumnInfo] {
        try await perform(id, database: table.database) { try await $0.columns(of: table) }
    }

    /// Fetch a page of rows from a table on an already-connected id, optionally sorted.
    public func fetchRows(_ table: TableRef, on id: UUID, limit: Int, offset: Int, sort: SortSpec? = nil) async throws -> QueryResult {
        try await perform(id, database: table.database) { try await $0.fetchRows(table, limit: limit, offset: offset, sort: sort) }
    }

    /// Exact row count for a table on an already-connected id.
    public func countRows(_ table: TableRef, on id: UUID) async throws -> Int {
        try await perform(id, database: table.database) { client in
            let result = try await client.query(client.dialect.countRowsSQL(table))
            guard let first = result.rows.first?.first, let value = first, let count = Int(value) else {
                return 0
            }
            return count
        }
    }

    /// Fast, approximate row count for a table (catalog stats), or nil if unavailable.
    public func estimatedRowCount(of table: TableRef, on id: UUID) async throws -> Int? {
        try await perform(id, database: table.database) { try await $0.estimatedRowCount(of: table) }
    }

    /// Tables larger than this trust the (instant) catalog estimate rather than
    /// running a potentially slow COUNT(*).
    public static let exactCountThreshold = 50_000

    /// A row count that's accurate for small tables and fast for large ones:
    /// big tables (estimate over the threshold) return the estimate; everything
    /// else — including un-analyzed tables with no estimate — runs an exact COUNT.
    public func rowCount(of table: TableRef, on id: UUID) async throws -> RowCount {
        if let estimate = try? await estimatedRowCount(of: table, on: id),
           estimate > Self.exactCountThreshold {
            return RowCount(value: estimate, isEstimate: true)
        }
        let exact = try await countRows(table, on: id)
        return RowCount(value: exact, isEstimate: false)
    }

    /// A table's primary-key column names (empty if it has none).
    public func primaryKeyColumns(of table: TableRef, on id: UUID) async throws -> [String] {
        try await perform(id, database: table.database) { try await $0.primaryKeyColumns(of: table) }
    }

    /// Outgoing foreign-key constraints from a table.
    public func foreignKeys(of table: TableRef, on id: UUID) async throws -> [ForeignKeyRef] {
        try await perform(id, database: table.database) { try await $0.foreignKeys(of: table) }
    }

    /// Full column definitions (type, nullability, default, PK) for a schema dump.
    public func columnDefinitions(of table: TableRef, on id: UUID) async throws -> [ColumnDefinition] {
        try await perform(id, database: table.database) { try await $0.columnDefinitions(of: table) }
    }

    // MARK: - Search

    /// Fetch a page of rows matching a cross-column search term.
    public func searchRows(
        _ table: TableRef,
        on id: UUID,
        columns: [String],
        term: String,
        limit: Int,
        offset: Int,
        sort: SortSpec? = nil
    ) async throws -> QueryResult {
        try await perform(id, database: table.database) {
            try await $0.query($0.dialect.searchRowsSQL(table, columns: columns, term: term, limit: limit, offset: offset, sort: sort))
        }
    }

    /// Exact count of rows matching a cross-column search term.
    public func searchRowCount(_ table: TableRef, on id: UUID, columns: [String], term: String) async throws -> Int {
        try await perform(id, database: table.database) { client in
            let result = try await client.query(client.dialect.searchCountSQL(table, columns: columns, term: term))
            guard let first = result.rows.first?.first, let value = first, let count = Int(value) else {
                return 0
            }
            return count
        }
    }

    /// Fetch a page of rows matching a single-column filter.
    public func filterRows(
        _ table: TableRef,
        on id: UUID,
        column: String,
        term: String,
        limit: Int,
        offset: Int,
        sort: SortSpec? = nil
    ) async throws -> QueryResult {
        try await perform(id, database: table.database) {
            try await $0.query($0.dialect.filterRowsSQL(table, column: column, term: term, limit: limit, offset: offset, sort: sort))
        }
    }

    /// Exact count for a single-column filter.
    public func filterRowCount(_ table: TableRef, on id: UUID, column: String, term: String) async throws -> Int {
        try await perform(id, database: table.database) { client in
            let result = try await client.query(client.dialect.filterCountSQL(table, column: column, term: term))
            guard let first = result.rows.first?.first, let value = first, let count = Int(value) else {
                return 0
            }
            return count
        }
    }

    // MARK: - Row mutations (DML)

    /// Insert one row. Columns/values must be equal length.
    public func insertRow(into table: TableRef, on id: UUID, columns: [String], values: [SQLValue]) async throws {
        try assertWritable(id)
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.insertRowSQL(table, columns: columns, values: values)) }
    }

    /// Update one row, identified by `predicates` (refuses an empty predicate set
    /// so we never issue an unrestricted UPDATE).
    public func updateRow(
        _ table: TableRef,
        on id: UUID,
        assignments: [(column: String, value: SQLValue)],
        predicates: [(column: String, value: SQLValue)]
    ) async throws {
        try assertWritable(id)
        guard !predicates.isEmpty else { throw DatabaseError.driver("Refusing to UPDATE without a WHERE clause.") }
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.updateRowSQL(table, assignments: assignments, predicates: predicates)) }
    }

    /// Delete one row, identified by `predicates` (refuses an empty predicate set).
    public func deleteRow(_ table: TableRef, on id: UUID, predicates: [(column: String, value: SQLValue)]) async throws {
        try assertWritable(id)
        guard !predicates.isEmpty else { throw DatabaseError.driver("Refusing to DELETE without a WHERE clause.") }
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.deleteRowSQL(table, predicates: predicates)) }
    }

    // MARK: - Table mutations (DDL)

    public func createTable(_ table: TableRef, on id: UUID, columns: [ColumnDefinition]) async throws {
        try assertWritable(id)
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.createTableSQL(table, columns: columns)) }
    }

    public func dropTable(_ table: TableRef, on id: UUID) async throws {
        try assertWritable(id)
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.dropTableSQL(table)) }
    }

    public func renameTable(_ table: TableRef, on id: UUID, to newName: String) async throws {
        try assertWritable(id)
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.renameTableSQL(table, to: newName)) }
    }

    public func addColumn(to table: TableRef, on id: UUID, column: ColumnDefinition) async throws {
        try assertWritable(id)
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.addColumnSQL(table, column: column)) }
    }

    public func dropColumn(_ column: String, from table: TableRef, on id: UUID) async throws {
        try assertWritable(id)
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.dropColumnSQL(table, column: column)) }
    }

    public func renameColumn(_ column: String, to newName: String, in table: TableRef, on id: UUID) async throws {
        try assertWritable(id)
        _ = try await perform(id, database: table.database) { try await $0.query($0.dialect.renameColumnSQL(table, column: column, to: newName)) }
    }

    // MARK: - Database mutations (DDL)

    /// `CREATE DATABASE name`, issued through the connection's default
    /// (maintenance) database. Caller should refresh the database list after.
    public func createDatabase(_ name: String, on id: UUID) async throws {
        try assertWritable(id)
        guard let conn = connections.first(where: { $0.id == id }) else { throw DatabaseError.notConnected }
        let sql = conn.driver.dialect.createDatabaseSQL(name)
        _ = try await perform(id, database: conn.database) { try await $0.query(sql) }
    }

    /// `DROP DATABASE name`. Postgres can't drop a database it is connected to,
    /// so the statement runs through a *different* maintenance database and any
    /// cached client to the target is closed first to release open sessions.
    public func dropDatabase(_ name: String, on id: UUID) async throws {
        try assertWritable(id)
        guard let conn = connections.first(where: { $0.id == id }) else { throw DatabaseError.notConnected }
        if name != conn.database {
            let targetKey = ClientKey(connectionID: id, database: name)
            if let client = clients[targetKey] {
                await client.close()
                clients[targetKey] = nil
            }
        }
        let maintenance = name == conn.database
            ? (conn.driver == .mysql ? conn.database : "postgres")
            : conn.database
        let sql = conn.driver.dialect.dropDatabaseSQL(name)
        _ = try await perform(id, database: maintenance) { try await $0.query(sql) }
    }

    // MARK: - Client resolution

    /// The concrete database name for a request, treating nil/empty as the
    /// connection's configured default database.
    private func resolvedDatabase(_ id: UUID, _ database: String?) -> String? {
        if let database, !database.isEmpty { return database }
        return connections.first { $0.id == id }?.database
    }

    /// Resolve the live client for a (connection, database) pair, lazily opening
    /// a per-database client when needed. MySQL serves every database from the
    /// primary client; Postgres opens (and caches) a separate pooled client per
    /// non-default database since it can't switch DB on a live connection.
    private func resolveClient(_ id: UUID, database: String?) async throws -> any DatabaseClient {
        guard let connection = connections.first(where: { $0.id == id }) else {
            throw DatabaseError.notConnected
        }
        let primaryKey = ClientKey(connectionID: id, database: connection.database)
        guard let primary = clients[primaryKey] else { throw DatabaseError.notConnected }

        let target = resolvedDatabase(id, database) ?? connection.database
        if connection.driver == .mysql || target == connection.database {
            return primary
        }

        let key = ClientKey(connectionID: id, database: target)
        if let existing = clients[key] { return existing }

        let password = try? secrets.get(connection.passwordKeychainKey)
        var dbConnection = connection
        dbConnection.database = target
        let (effective, dbPassword) = try await resolvedEndpoint(for: dbConnection, password: password)
        let client = makeClient(effective, dbPassword)
        do {
            try await client.connect()
        } catch {
            await client.close()
            throw error
        }
        clients[key] = client
        return client
    }

    /// Run a client operation, demoting the connection's status if the failure
    /// indicates the connection was lost (so the UI can offer to reconnect).
    /// Normal query errors (e.g. SQL syntax) are re-thrown without demotion.
    /// A lost *secondary* (non-default Postgres) client is dropped without
    /// demoting the whole connection — only losing the primary does that.
    private func perform<T>(_ id: UUID, database: String? = nil, _ body: (any DatabaseClient) async throws -> T) async throws -> T {
        let client = try await resolveClient(id, database: database)
        do {
            return try await body(client)
        } catch {
            if let dbError = error as? DatabaseError, dbError.isConnectionLost,
               let connection = connections.first(where: { $0.id == id }) {
                let target = resolvedDatabase(id, database) ?? connection.database
                clients[ClientKey(connectionID: id, database: target)] = nil
                if connection.driver == .mysql || target == connection.database {
                    // Primary client lost — tear down everything and demote.
                    await disconnect(id)
                    status[id] = .failed(dbError.userMessage)
                }
            }
            throw error
        }
    }

    // MARK: - Helpers

    private func assertWritable(_ id: UUID) throws {
        if isReadOnly(id) { throw DatabaseError.readOnly }
    }

    private func assertWritableSQL(_ sql: String, on id: UUID) throws {
        if isReadOnly(id), SQLWriteDetector.containsWrite(sql) {
            throw DatabaseError.readOnly
        }
    }

    /// When SSH is enabled, open a local forward and return a copy of the
    /// connection aimed at `127.0.0.1:localPort`.
    private func resolvedEndpoint(
        for connection: Connection,
        password: String?
    ) async throws -> (Connection, String?) {
        guard connection.ssh.enabled else { return (connection, password) }

        let sshPassword: String?
        if let key = connection.ssh.passwordKeychainKey {
            sshPassword = try secrets.get(key)
        } else {
            sshPassword = nil
        }

        let localPort: Int
        do {
            localPort = try await sshTunnels.open(
                connectionID: connection.id,
                config: connection.ssh,
                targetHost: connection.host,
                targetPort: connection.port,
                password: sshPassword
            )
        } catch let tunnelError as SSHTunnelError {
            switch tunnelError {
            case .invalidConfiguration(let message):
                throw DatabaseError.driver("SSH: \(message)")
            case .launchFailed(let message):
                throw DatabaseError.driver("SSH tunnel failed: \(message)")
            case .noFreePort:
                throw DatabaseError.driver("SSH tunnel failed: no free local port.")
            }
        }

        var tunneled = connection
        tunneled.host = "127.0.0.1"
        tunneled.port = localPort
        return (tunneled, password)
    }

    private static func message(for error: Error) -> String {
        if let dbError = error as? DatabaseError { return dbError.userMessage }
        if let tunnelError = error as? SSHTunnelError {
            switch tunnelError {
            case .invalidConfiguration(let message): return "SSH: \(message)"
            case .launchFailed(let message): return "SSH tunnel failed: \(message)"
            case .noFreePort: return "SSH tunnel failed: no free local port."
            }
        }
        return String(describing: error)
    }
}
