// SQLDialect.swift
import Foundation

/// A schema-qualified table reference surfaced by introspection.
public struct TableRef: Identifiable, Hashable, Sendable {
    public let schema: String
    public let name: String

    public var id: String { "\(schema).\(name)" }

    public init(schema: String, name: String) {
        self.schema = schema
        self.name = name
    }
}

/// A sort applied to a browsed table: column name + direction.
public struct SortSpec: Sendable, Equatable {
    public let column: String
    public let ascending: Bool

    public init(column: String, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }
}

/// Per-driver SQL generation. Kept as pure functions so identifier quoting and
/// query shaping can be unit-tested without a live database.
public enum SQLDialect: Sendable {
    case postgres
    case mysql

    /// Quote an identifier, escaping the closing quote char by doubling it.
    /// Postgres uses double quotes; MySQL uses backticks.
    public func quote(_ identifier: String) -> String {
        switch self {
        case .postgres:
            return "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        case .mysql:
            return "`" + identifier.replacingOccurrences(of: "`", with: "``") + "`"
        }
    }

    /// Fully-qualified, quoted `schema.table`.
    public func qualifiedName(_ table: TableRef) -> String {
        "\(quote(table.schema)).\(quote(table.name))"
    }

    /// SQL listing user tables (excludes system schemas).
    public var listTablesSQL: String {
        switch self {
        case .postgres:
            return """
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_type = 'BASE TABLE'
              AND table_schema NOT IN ('pg_catalog', 'information_schema')
            ORDER BY table_schema, table_name
            """
        case .mysql:
            return """
            SELECT table_schema, table_name
            FROM information_schema.tables
            WHERE table_type = 'BASE TABLE'
              AND table_schema = DATABASE()
            ORDER BY table_name
            """
        }
    }

    /// Paged `SELECT *` over a table. `limit`/`offset` are clamped to >= 0 and
    /// inlined as integers (never user strings), so no injection surface. The
    /// sort column is quoted (identifier-safe); direction is a fixed keyword.
    public func selectRowsSQL(_ table: TableRef, limit: Int, offset: Int, sort: SortSpec? = nil) -> String {
        let safeLimit = max(0, limit)
        let safeOffset = max(0, offset)
        var sql = "SELECT * FROM \(qualifiedName(table))"
        if let sort {
            sql += " ORDER BY \(quote(sort.column)) \(sort.ascending ? "ASC" : "DESC")"
        }
        sql += " LIMIT \(safeLimit) OFFSET \(safeOffset)"
        return sql
    }

    /// Exact row count for a table.
    public func countRowsSQL(_ table: TableRef) -> String {
        "SELECT COUNT(*) FROM \(qualifiedName(table))"
    }
}

public extension Connection.Driver {
    var dialect: SQLDialect {
        switch self {
        case .postgres: .postgres
        case .mysql: .mysql
        }
    }
}
