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
    /// inlined as integers (never user strings), so no injection surface.
    public func selectRowsSQL(_ table: TableRef, limit: Int, offset: Int) -> String {
        let safeLimit = max(0, limit)
        let safeOffset = max(0, offset)
        return "SELECT * FROM \(qualifiedName(table)) LIMIT \(safeLimit) OFFSET \(safeOffset)"
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
