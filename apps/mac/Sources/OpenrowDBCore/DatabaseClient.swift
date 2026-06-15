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

    /// Tear down the connection and release all resources. Idempotent.
    func close() async
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
