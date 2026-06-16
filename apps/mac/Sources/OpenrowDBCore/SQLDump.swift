// SQLDump.swift
import Foundation

/// Builds a portable logical SQL dump (schema + data) from introspected tables.
///
/// This is a *logical* dump — `DROP`/`CREATE TABLE` + per-row `INSERT` — meant
/// for moving small databases between servers or for backup, not a byte-exact
/// `pg_dump`/`mysqldump` replacement. Known v1 limitations (documented for the
/// UI to surface): sequence/identity defaults are dropped (so re-imported keys
/// aren't auto-generated), foreign-key/check constraints and indexes beyond the
/// primary key aren't emitted, and tables are dumped in catalog order — so a
/// dump with FK relationships may need ordering or constraint handling on import.
public enum SQLDumpBuilder: Sendable {
    /// One table's contribution to a dump: its column definitions (for `CREATE`)
    /// and its rows (`data.columns` drives the `INSERT` column list).
    public struct TableDump: Sendable {
        public let table: TableRef
        public let columns: [ColumnDefinition]
        public let data: QueryResult

        public init(table: TableRef, columns: [ColumnDefinition], data: QueryResult) {
            self.table = table
            self.columns = columns
            self.data = data
        }
    }

    public struct Options: Sendable {
        public var dropIfExists: Bool
        public var createTable: Bool
        public var includeData: Bool

        public init(dropIfExists: Bool = true, createTable: Bool = true, includeData: Bool = true) {
            self.dropIfExists = dropIfExists
            self.createTable = createTable
            self.includeData = includeData
        }
    }

    public static func build(_ dumps: [TableDump], dialect: SQLDialect, options: Options = Options()) -> String {
        var out = "-- OpenrowDB SQL dump\n"
        out += "-- dialect: \(dialectName(dialect))\n\n"

        for dump in dumps {
            let qualified = dialect.qualifiedName(dump.table)
            out += "-- Table: \(dump.table.schema).\(dump.table.name)\n"

            if options.dropIfExists {
                out += "DROP TABLE IF EXISTS \(qualified);\n"
            }
            if options.createTable, !dump.columns.isEmpty {
                out += dialect.createTableSQL(dump.table, columns: dump.columns) + ";\n"
            }
            if options.includeData, !dump.data.columns.isEmpty, !dump.data.rows.isEmpty {
                out += "\n"
                for row in dump.data.rows {
                    let values = row.map { $0.map(SQLValue.text) ?? .null }
                    out += dialect.insertRowSQL(dump.table, columns: dump.data.columns, values: values) + ";\n"
                }
            }
            out += "\n"
        }
        return out
    }

    private static func dialectName(_ dialect: SQLDialect) -> String {
        switch dialect {
        case .postgres: return "postgres"
        case .mysql: return "mysql"
        }
    }
}
