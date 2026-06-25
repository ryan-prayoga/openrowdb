// SchemaCatalog.swift
import Foundation

/// Snapshot of one connection's schema: tables + (lazily) columns. Used by the
/// SQL completion provider so suggestions reflect the live database. The
/// snapshot is a value type so the completion engine can run off the main
/// actor without races; `SchemaCatalog` (below) owns the mutable cache.
public struct SchemaSnapshot: Sendable, Equatable {
    public let tables: [TableRef]
    public let columnsByTable: [String: [ColumnInfo]]

    public init(tables: [TableRef], columnsByTable: [String: [ColumnInfo]] = [:]) {
        self.tables = tables
        self.columnsByTable = columnsByTable
    }

    public static let empty = SchemaSnapshot(tables: [], columnsByTable: [:])

    public func columns(of table: TableRef) -> [ColumnInfo] {
        columnsByTable[table.id] ?? []
    }

    public func tables(named name: String) -> [TableRef] {
        let lower = name.lowercased()
        return tables.filter { $0.name.lowercased() == lower }
    }
}

@MainActor
@Observable
public final class SchemaCatalog {
    public private(set) var snapshot: SchemaSnapshot = .empty
    public private(set) var isRefreshing = false
    public private(set) var lastError: String?

    /// Database the completion catalog reflects. `nil` = the connection's
    /// default database. Switching it drops the cached snapshot so stale tables
    /// from the previous database don't linger until the next refresh lands.
    public var database: String? {
        didSet {
            if database != oldValue { snapshot = .empty }
        }
    }

    private let connectionID: UUID
    private let manager: ConnectionManager

    public init(connectionID: UUID, manager: ConnectionManager) {
        self.connectionID = connectionID
        self.manager = manager
    }

    public func refresh() async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            let tables = try await manager.tables(on: connectionID, database: database)
            var byTable = snapshot.columnsByTable
            for ref in tables where byTable[ref.id] == nil {
                if let cols = try? await manager.columns(of: ref, on: connectionID) {
                    byTable[ref.id] = cols
                }
            }
            snapshot = SchemaSnapshot(tables: tables, columnsByTable: byTable)
        } catch let dbError as DatabaseError {
            lastError = dbError.userMessage
        } catch {
            lastError = String(reflecting: error)
        }
    }
}
