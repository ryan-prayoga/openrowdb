// DatabaseClient.swift
import Foundation

/// A live connection to one database, abstracted over the underlying driver.
///
/// Implementations own their NIO resources and must be `close()`d when done.
public protocol DatabaseClient: Sendable {
    /// Open the connection and verify it is usable. Throws on failure.
    func connect() async throws

    /// Run a SQL string and return its result set.
    func query(_ sql: String) async throws -> QueryResult

    /// The SQL dialect this client speaks (drives introspection queries).
    var dialect: SQLDialect { get }

    /// Tear down the connection and release all resources. Idempotent.
    func close() async
}

public extension DatabaseClient {
    /// List user tables and views via `information_schema`.
    func listTables() async throws -> [TableRef] {
        let result = try await query(dialect.listTablesSQL)
        return result.rows.compactMap { row in
            guard row.count >= 2, let schema = row[0], let name = row[1] else { return nil }
            let kind: TableRef.Kind = (row.count >= 3 && row[2]?.uppercased() == "VIEW") ? .view : .table
            return TableRef(schema: schema, name: name, kind: kind)
        }
    }

    /// A table's columns with their SQL data types.
    func columns(of table: TableRef) async throws -> [ColumnInfo] {
        let result = try await query(dialect.listColumnsSQL(table))
        return result.rows.compactMap { row in
            guard row.count >= 2, let name = row[0], let type = row[1] else { return nil }
            return ColumnInfo(name: name, type: type)
        }
    }

    /// Approximate row count from catalog stats, or nil if unavailable.
    func estimatedRowCount(of table: TableRef) async throws -> Int? {
        let result = try await query(dialect.estimatedRowCountSQL(table))
        guard let cell = result.rows.first?.first, let value = cell, let number = Double(value) else {
            return nil
        }
        return number < 0 ? nil : Int(number)
    }

    /// Fetch a page of rows from a table, optionally sorted.
    func fetchRows(_ table: TableRef, limit: Int, offset: Int, sort: SortSpec? = nil) async throws -> QueryResult {
        try await query(dialect.selectRowsSQL(table, limit: limit, offset: offset, sort: sort))
    }
}

/// Errors surfaced by the Core database layer.
public enum DatabaseError: Error, Sendable, Equatable {
    /// Host could not be resolved or the address was malformed.
    case invalidAddress(String)
    /// The connection was used after `close()`.
    case notConnected
    /// Driver-level failure, with the underlying message preserved.
    case driver(String)
}

public extension DatabaseError {
    /// A human-readable message suitable for showing in the UI. Driver errors
    /// are pattern-matched to friendly text, falling back to the raw string.
    var userMessage: String {
        switch self {
        case .invalidAddress(let host):
            return "Couldn't resolve host \u{201C}\(host)\u{201D}. Check the hostname."
        case .notConnected:
            return "Not connected."
        case .driver(let raw):
            return Self.humanize(raw)
        }
    }

    private static func humanize(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("connectionrefused") || lower.contains("connection refused") {
            return "Connection refused — is the server running and reachable on that host/port?"
        }
        if lower.contains("circuitbreakertripped") {
            return "Couldn't establish a connection. Check the host, port, and that the server is running."
        }
        if lower.contains("authentication") || lower.contains("password") {
            return "Authentication failed — check the username and password."
        }
        if lower.contains("does not exist") || lower.contains("unknown database") {
            return "Database or role not found — check the database name and user."
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return "Connection timed out — the server didn't respond in time."
        }
        if lower.contains("no such host") || lower.contains("nodename nor servname") {
            return "Host not found — check the hostname."
        }
        return "Connection failed: \(raw)"
    }

    /// Whether this error indicates the live connection was lost (vs. a normal
    /// query error like a syntax mistake). Used to demote a connection's status.
    var isConnectionLost: Bool {
        switch self {
        case .notConnected:
            return true
        case .invalidAddress:
            return false
        case .driver(let raw):
            let lower = raw.lowercased()
            if lower.contains("not connected") || lower.contains("broken pipe")
                || lower.contains("shutdown") || lower.contains("closed connection")
                || lower.contains("connectionclosed") || lower.contains("server closed") {
                return true
            }
            return lower.contains("connection") && (lower.contains("closed") || lower.contains("reset"))
        }
    }
}

public enum DatabaseClientFactory {
    /// Build a driver-specific client for a connection descriptor.
    ///
    /// - Parameters:
    ///   - connection: The connection metadata.
    ///   - password: Plaintext password resolved from the secret store (may be nil).
    public static func make(for connection: Connection, password: String?) -> any DatabaseClient {
        switch connection.driver {
        case .postgres:
            PostgresDriver(connection: connection, password: password)
        case .mysql:
            MySQLDriver(connection: connection, password: password)
        }
    }
}
