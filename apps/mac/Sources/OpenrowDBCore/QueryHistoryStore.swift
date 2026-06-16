// QueryHistoryStore.swift
import Foundation
import GRDB
import Observation

/// One executed query, persisted for the History inspector.
///
/// `connectionID` ties the entry back to a saved `Connection.id`. `error` is set
/// only for failed runs; on success it stays nil and `rowsAffected` carries the
/// driver-reported count (when applicable).
public struct HistoryEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let connectionID: UUID
    public let sql: String
    public let executedAt: Date
    public let durationMs: Int
    public let rowsAffected: Int?
    public let error: String?

    public init(
        id: UUID = UUID(),
        connectionID: UUID,
        sql: String,
        executedAt: Date = Date(),
        durationMs: Int,
        rowsAffected: Int? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.connectionID = connectionID
        self.sql = sql
        self.executedAt = executedAt
        self.durationMs = durationMs
        self.rowsAffected = rowsAffected
        self.error = error
    }
}

// MARK: - Errors

/// Errors thrown by `QueryHistoryStore` decoding/encoding paths.
public enum HistoryStoreError: Error, Sendable {
    case malformedUUID
}

// MARK: - GRDB record conformance

extension HistoryEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "history_entries"

    enum Columns {
        static let id = Column("id")
        static let connectionID = Column("connection_id")
        static let sql = Column("sql")
        static let executedAt = Column("executed_at")
        static let durationMs = Column("duration_ms")
        static let rowsAffected = Column("rows_affected")
        static let error = Column("error")
    }

    public init(row: Row) throws {
        // UUIDs are stored as TEXT so we can round-trip them through plain SQL
        // without worrying about endianness or BLOB encoding.
        let idString: String = row[Columns.id]
        let connectionIDString: String = row[Columns.connectionID]
        guard let id = UUID(uuidString: idString),
              let connectionID = UUID(uuidString: connectionIDString) else {
            throw HistoryStoreError.malformedUUID
        }
        self.id = id
        self.connectionID = connectionID
        self.sql = row[Columns.sql]
        self.executedAt = row[Columns.executedAt]
        self.durationMs = row[Columns.durationMs]
        self.rowsAffected = row[Columns.rowsAffected]
        self.error = row[Columns.error]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.connectionID] = connectionID.uuidString
        container[Columns.sql] = sql
        container[Columns.executedAt] = executedAt
        container[Columns.durationMs] = durationMs
        container[Columns.rowsAffected] = rowsAffected
        container[Columns.error] = error
    }
}

// MARK: - Store

/// Async-only GRDB-backed store for executed query history.
///
/// Backed by a single SQLite file managed by a `DatabasePool` (one writer, many
/// readers). All operations are `async throws` so callers can offload off the
/// main actor cleanly. Conforms to `Observable` so SwiftUI views can inject it
/// via `.environment(_:)` alongside `ConnectionManager`.
@Observable
public final class QueryHistoryStore: @unchecked Sendable {
    @ObservationIgnored
    private let dbPool: DatabasePool

    /// - Parameter fileURL: SQLite file location. Defaults to
    ///   `~/Library/Application Support/OpenrowDB/history.sqlite`.
    public init(fileURL: URL? = nil) throws {
        let resolvedURL: URL
        if let fileURL {
            resolvedURL = fileURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolvedURL = support
                .appendingPathComponent("OpenrowDB", isDirectory: true)
                .appendingPathComponent("history.sqlite", isDirectory: false)
        }

        // Ensure parent dir exists; GRDB will create the file itself.
        try FileManager.default.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        self.dbPool = try DatabasePool(path: resolvedURL.path)
        try Self.migrator.migrate(dbPool)
    }

    // MARK: Migrations

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_history_entries") { db in
            try db.create(table: HistoryEntry.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("connection_id", .text).notNull().indexed()
                t.column("sql", .text).notNull()
                t.column("executed_at", .datetime).notNull().indexed()
                t.column("duration_ms", .integer).notNull()
                t.column("rows_affected", .integer)
                t.column("error", .text)
            }
        }
        return migrator
    }

    // MARK: Public API

    /// Persist one executed-query record.
    public func record(_ entry: HistoryEntry) async throws {
        try await dbPool.write { db in
            try entry.insert(db)
        }
    }

    /// All entries for a given connection, newest first. Pass `limit` to cap the result.
    public func entries(forConnection connectionID: UUID, limit: Int? = nil) async throws -> [HistoryEntry] {
        try await dbPool.read { db in
            var request = HistoryEntry
                .filter(HistoryEntry.Columns.connectionID == connectionID.uuidString)
                .order(HistoryEntry.Columns.executedAt.desc)
            if let limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    /// All entries across every connection, newest first. Useful for a global history view.
    public func allEntries(limit: Int? = nil) async throws -> [HistoryEntry] {
        try await dbPool.read { db in
            var request = HistoryEntry.order(HistoryEntry.Columns.executedAt.desc)
            if let limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    /// Delete a single entry by `id`. No-op if absent.
    public func delete(id: UUID) async throws {
        try await dbPool.write { db in
            _ = try HistoryEntry.deleteOne(db, key: id.uuidString)
        }
    }

    /// Wipe every history row for a given connection.
    public func clear(connectionID: UUID) async throws {
        try await dbPool.write { db in
            _ = try HistoryEntry
                .filter(HistoryEntry.Columns.connectionID == connectionID.uuidString)
                .deleteAll(db)
        }
    }

    /// Wipe every history row regardless of connection.
    public func clearAll() async throws {
        try await dbPool.write { db in
            _ = try HistoryEntry.deleteAll(db)
        }
    }
}
