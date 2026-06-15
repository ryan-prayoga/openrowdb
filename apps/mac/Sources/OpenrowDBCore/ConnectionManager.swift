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
    private var clients: [UUID: any DatabaseClient] = [:]

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

    /// Update metadata, and the password when a new one is supplied (nil = keep existing).
    public func update(_ connection: Connection, password: String?) throws {
        if let password {
            try secrets.set(password, for: connection.passwordKeychainKey)
        }
        try store.upsert(connection)
        connections = try store.load()
    }

    /// Disconnect, then delete the client, secret, and metadata.
    public func remove(_ connection: Connection) async throws {
        await disconnect(connection.id)
        try secrets.remove(connection.passwordKeychainKey)
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

        let client = makeClient(connection, password)
        do {
            try await client.connect()
            clients[id] = client
            status[id] = .connected
        } catch {
            await client.close()
            status[id] = .failed(Self.message(for: error))
        }
    }

    /// Close and forget the live client for an id.
    public func disconnect(_ id: UUID) async {
        if let client = clients.removeValue(forKey: id) {
            await client.close()
        }
        if status[id] != nil {
            status[id] = .disconnected
        }
    }

    /// Run SQL against an already-connected id.
    public func run(_ sql: String, on id: UUID) async throws -> QueryResult {
        guard let client = clients[id] else {
            throw DatabaseError.notConnected
        }
        return try await client.query(sql)
    }

    // MARK: - Helpers

    private static func message(for error: Error) -> String {
        if case let DatabaseError.driver(message) = error { return message }
        return String(describing: error)
    }
}
