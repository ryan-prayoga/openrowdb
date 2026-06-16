// QuerySnippetStore.swift
import Foundation
import GRDB
import Observation

/// A user-saved SQL snippet, bookmarked per connection (unlike ephemeral history).
public struct SnippetEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let connectionID: UUID
    public var title: String
    public var sql: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        connectionID: UUID,
        title: String,
        sql: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.connectionID = connectionID
        self.title = title
        self.sql = sql
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum SnippetStoreError: Error, Sendable {
    case malformedUUID
}

extension SnippetEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "snippet_entries"

    enum Columns {
        static let id = Column("id")
        static let connectionID = Column("connection_id")
        static let title = Column("title")
        static let sql = Column("sql")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }

    public init(row: Row) throws {
        let idString: String = row[Columns.id]
        let connectionIDString: String = row[Columns.connectionID]
        guard let id = UUID(uuidString: idString),
              let connectionID = UUID(uuidString: connectionIDString) else {
            throw SnippetStoreError.malformedUUID
        }
        self.id = id
        self.connectionID = connectionID
        self.title = row[Columns.title]
        self.sql = row[Columns.sql]
        self.createdAt = row[Columns.createdAt]
        self.updatedAt = row[Columns.updatedAt]
    }

    public func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString
        container[Columns.connectionID] = connectionID.uuidString
        container[Columns.title] = title
        container[Columns.sql] = sql
        container[Columns.createdAt] = createdAt
        container[Columns.updatedAt] = updatedAt
    }
}

@Observable
public final class QuerySnippetStore: @unchecked Sendable {
    @ObservationIgnored
    private let dbPool: DatabasePool

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
                .appendingPathComponent("snippets.sqlite", isDirectory: false)
        }

        try FileManager.default.createDirectory(
            at: resolvedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        self.dbPool = try DatabasePool(path: resolvedURL.path)
        try Self.migrator.migrate(dbPool)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_create_snippet_entries") { db in
            try db.create(table: SnippetEntry.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("connection_id", .text).notNull().indexed()
                t.column("title", .text).notNull()
                t.column("sql", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull().indexed()
            }
        }
        return migrator
    }

    public func save(_ entry: SnippetEntry) async throws {
        try await dbPool.write { db in
            try entry.save(db)
        }
    }

    public func upsert(connectionID: UUID, title: String, sql: String) async throws -> SnippetEntry {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = SnippetEntry(
            connectionID: connectionID,
            title: trimmedTitle.isEmpty ? "Untitled" : trimmedTitle,
            sql: sql
        )
        try await save(entry)
        return entry
    }

    public func entries(forConnection connectionID: UUID) async throws -> [SnippetEntry] {
        try await dbPool.read { db in
            try SnippetEntry
                .filter(SnippetEntry.Columns.connectionID == connectionID.uuidString)
                .order(SnippetEntry.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    public func delete(id: UUID) async throws {
        try await dbPool.write { db in
            _ = try SnippetEntry.deleteOne(db, key: id.uuidString)
        }
    }

    public func clear(connectionID: UUID) async throws {
        try await dbPool.write { db in
            _ = try SnippetEntry
                .filter(SnippetEntry.Columns.connectionID == connectionID.uuidString)
                .deleteAll(db)
        }
    }
}