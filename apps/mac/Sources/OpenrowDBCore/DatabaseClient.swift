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
    /// List user tables via `information_schema`.
    func listTables() async throws -> [TableRef] {
        let result = try await query(dialect.listTablesSQL)
        return result.rows.compactMap { row in
            guard row.count >= 2, let schema = row[0], let name = row[1] else { return nil }
            return TableRef(schema: schema, name: name)
        }
    }

    /// Fetch a page of rows from a table.
    func fetchRows(_ table: TableRef, limit: Int, offset: Int) async throws -> QueryResult {
        try await query(dialect.selectRowsSQL(table, limit: limit, offset: offset))
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
