// SQLMutations.swift
import Foundation

/// A value bound into a generated DML statement. Rendered as an inline SQL
/// literal (single quotes escaped), letting the server coerce the string to the
/// column's real type — the same injection-safe inlining the browse/read path
/// already uses. `null` renders the `NULL` keyword (and `IS NULL` in predicates).
public enum SQLValue: Sendable, Equatable {
    case null
    case text(String)
}

/// A column as defined in CREATE / ALTER TABLE. Richer than `ColumnInfo` (which
/// only carries name + type for display): it also tracks nullability, primary
/// key membership, and an optional raw default expression. The stable `id` lets
/// the structure editor track renames across edits (same id, new name).
public struct ColumnDefinition: Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var type: String
    public var isNullable: Bool
    public var isPrimaryKey: Bool
    /// Raw SQL default expression (e.g. `0`, `now()`, `'pending'`), inlined
    /// verbatim. Owner-authored DDL, so it is not quoted for the caller.
    public var defaultValue: String?

    public init(
        id: UUID = UUID(),
        name: String = "",
        type: String = "",
        isNullable: Bool = true,
        isPrimaryKey: Bool = false,
        defaultValue: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.isNullable = isNullable
        self.isPrimaryKey = isPrimaryKey
        self.defaultValue = defaultValue
    }
}

public extension SQLDialect {
    // MARK: - Literals

    /// Render a bound value as an inline SQL literal.
    func render(_ value: SQLValue) -> String {
        switch value {
        case .null: return "NULL"
        case .text(let s): return quoteLiteral(s)
        }
    }

    // MARK: - Row mutations (DML)

    /// `INSERT INTO t (cols...) VALUES (literals...)`. With no columns, emits the
    /// dialect's "all defaults" form. `columns`/`values` must be equal length.
    func insertRowSQL(_ table: TableRef, columns: [String], values: [SQLValue]) -> String {
        guard !columns.isEmpty else {
            switch self {
            case .postgres: return "INSERT INTO \(qualifiedName(table)) DEFAULT VALUES"
            case .mysql: return "INSERT INTO \(qualifiedName(table)) () VALUES ()"
            }
        }
        let cols = columns.map(quote).joined(separator: ", ")
        let vals = values.map(render).joined(separator: ", ")
        return "INSERT INTO \(qualifiedName(table)) (\(cols)) VALUES (\(vals))"
    }

    /// `UPDATE t SET col = literal, ... WHERE pred AND ...`. The predicate list
    /// must be non-empty — callers guard against an unrestricted UPDATE.
    func updateRowSQL(
        _ table: TableRef,
        assignments: [(column: String, value: SQLValue)],
        predicates: [(column: String, value: SQLValue)]
    ) -> String {
        let sets = assignments.map { "\(quote($0.column)) = \(render($0.value))" }.joined(separator: ", ")
        return "UPDATE \(qualifiedName(table)) SET \(sets) WHERE \(whereClause(predicates))"
    }

    /// `DELETE FROM t WHERE pred AND ...`. The predicate list must be non-empty.
    func deleteRowSQL(_ table: TableRef, predicates: [(column: String, value: SQLValue)]) -> String {
        "DELETE FROM \(qualifiedName(table)) WHERE \(whereClause(predicates))"
    }

    /// Equality predicate joined by AND. A `null` value becomes `IS NULL` so a
    /// row identified by a NULL cell still matches.
    func whereClause(_ predicates: [(column: String, value: SQLValue)]) -> String {
        predicates.map { predicate in
            switch predicate.value {
            case .null: return "\(quote(predicate.column)) IS NULL"
            case .text(let s): return "\(quote(predicate.column)) = \(quoteLiteral(s))"
            }
        }.joined(separator: " AND ")
    }

    // MARK: - Search

    /// Case-insensitive substring match across the given columns, OR'd together.
    /// Uses `POSITION`/`LOCATE` over a text cast (not LIKE) so the term needs no
    /// wildcard escaping — only the literal's single quotes, which `quoteLiteral`
    /// handles. NULL cells cast to NULL and simply don't match.
    func searchPredicate(columns: [String], term: String) -> String {
        let needle = quoteLiteral(term)
        let clauses = columns.map { column -> String in
            switch self {
            case .postgres:
                return "POSITION(LOWER(\(needle)) IN LOWER(CAST(\(quote(column)) AS TEXT))) > 0"
            case .mysql:
                return "LOCATE(LOWER(\(needle)), LOWER(CAST(\(quote(column)) AS CHAR))) > 0"
            }
        }
        return "(" + clauses.joined(separator: " OR ") + ")"
    }

    /// Paged `SELECT *` filtered by a cross-column search term.
    func searchRowsSQL(
        _ table: TableRef,
        columns: [String],
        term: String,
        limit: Int,
        offset: Int,
        sort: SortSpec? = nil
    ) -> String {
        let safeLimit = max(0, limit)
        let safeOffset = max(0, offset)
        var sql = "SELECT * FROM \(qualifiedName(table)) WHERE \(searchPredicate(columns: columns, term: term))"
        if let sort {
            sql += " ORDER BY \(quote(sort.column)) \(sort.ascending ? "ASC" : "DESC")"
        }
        sql += " LIMIT \(safeLimit) OFFSET \(safeOffset)"
        return sql
    }

    /// Exact count of rows matching a cross-column search term.
    func searchCountSQL(_ table: TableRef, columns: [String], term: String) -> String {
        "SELECT COUNT(*) FROM \(qualifiedName(table)) WHERE \(searchPredicate(columns: columns, term: term))"
    }

    /// Paged `SELECT *` filtered by a single-column substring match.
    func filterRowsSQL(
        _ table: TableRef,
        column: String,
        term: String,
        limit: Int,
        offset: Int,
        sort: SortSpec? = nil
    ) -> String {
        searchRowsSQL(table, columns: [column], term: term, limit: limit, offset: offset, sort: sort)
    }

    /// Exact count for a single-column filter.
    func filterCountSQL(_ table: TableRef, column: String, term: String) -> String {
        searchCountSQL(table, columns: [column], term: term)
    }

    // MARK: - Explain

    /// Wrap arbitrary SQL in a dialect-appropriate EXPLAIN statement.
    func explainSQL(_ sql: String) -> String {
        switch self {
        case .postgres:
            return "EXPLAIN (FORMAT TEXT) \(sql)"
        case .mysql:
            return "EXPLAIN \(sql)"
        }
    }

    // MARK: - Foreign keys

    /// SQL returning outgoing FKs: local column, referenced schema, table, column.
    func foreignKeysSQL(_ table: TableRef) -> String {
        switch self {
        case .postgres:
            return """
            SELECT kcu.column_name, ccu.table_schema, ccu.table_name, ccu.column_name
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
              ON tc.constraint_name = kcu.constraint_name
             AND tc.table_schema = kcu.table_schema
            JOIN information_schema.constraint_column_usage ccu
              ON ccu.constraint_name = tc.constraint_name
             AND ccu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND tc.table_schema = \(quoteLiteral(table.schema))
              AND tc.table_name = \(quoteLiteral(table.name))
            ORDER BY kcu.ordinal_position
            """
        case .mysql:
            return """
            SELECT kcu.column_name, kcu.referenced_table_schema, kcu.referenced_table_name, kcu.referenced_column_name
            FROM information_schema.key_column_usage kcu
            JOIN information_schema.table_constraints tc
              ON kcu.constraint_name = tc.constraint_name
             AND kcu.table_schema = tc.table_schema
            WHERE tc.constraint_type = 'FOREIGN KEY'
              AND kcu.table_schema = \(quoteLiteral(table.schema))
              AND kcu.table_name = \(quoteLiteral(table.name))
            ORDER BY kcu.ordinal_position
            """
        }
    }

    // MARK: - Primary key introspection

    /// SQL returning a table's primary-key column names in key order. Used to
    /// build safe WHERE clauses for row edit/delete.
    func primaryKeyColumnsSQL(_ table: TableRef) -> String {
        switch self {
        case .postgres:
            return """
            SELECT a.attname
            FROM pg_index i
            JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
            WHERE i.indrelid = \(quoteLiteral(qualifiedName(table)))::regclass AND i.indisprimary
            ORDER BY array_position(i.indkey, a.attnum)
            """
        case .mysql:
            return """
            SELECT column_name
            FROM information_schema.key_column_usage
            WHERE table_schema = \(quoteLiteral(table.schema))
              AND table_name = \(quoteLiteral(table.name))
              AND constraint_name = 'PRIMARY'
            ORDER BY ordinal_position
            """
        }
    }

    /// SQL returning a table's full column definitions for a schema dump: name,
    /// SQL type, nullability ('YES'/'NO'), and the raw default expression (or
    /// NULL). Postgres reads `pg_catalog` so `format_type` yields precise types
    /// (e.g. `character varying(255)`, `numeric(10,2)`); MySQL uses `column_type`.
    func fullColumnsSQL(_ table: TableRef) -> String {
        switch self {
        case .postgres:
            return """
            SELECT a.attname,
                   format_type(a.atttypid, a.atttypmod),
                   CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END,
                   pg_get_expr(d.adbin, d.adrelid)
            FROM pg_attribute a
            LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
            WHERE a.attrelid = \(quoteLiteral(qualifiedName(table)))::regclass
              AND a.attnum > 0 AND NOT a.attisdropped
            ORDER BY a.attnum
            """
        case .mysql:
            return """
            SELECT column_name, column_type, is_nullable, column_default
            FROM information_schema.columns
            WHERE table_schema = \(quoteLiteral(table.schema))
              AND table_name = \(quoteLiteral(table.name))
            ORDER BY ordinal_position
            """
        }
    }

    // MARK: - Table mutations (DDL)

    /// `CREATE TABLE t (col defs..., PRIMARY KEY (...))`. The PRIMARY KEY clause
    /// is appended only when at least one column is flagged.
    func createTableSQL(_ table: TableRef, columns: [ColumnDefinition]) -> String {
        var parts = columns.map(columnClause)
        let pkColumns = columns.filter(\.isPrimaryKey).map { quote($0.name) }
        if !pkColumns.isEmpty {
            parts.append("PRIMARY KEY (\(pkColumns.joined(separator: ", ")))")
        }
        return "CREATE TABLE \(qualifiedName(table)) (\(parts.joined(separator: ", ")))"
    }

    func dropTableSQL(_ table: TableRef) -> String {
        "DROP TABLE \(qualifiedName(table))"
    }

    func createDatabaseSQL(_ name: String) -> String {
        "CREATE DATABASE \(quote(name))"
    }

    func dropDatabaseSQL(_ name: String) -> String {
        "DROP DATABASE \(quote(name))"
    }

    func renameTableSQL(_ table: TableRef, to newName: String) -> String {
        "ALTER TABLE \(qualifiedName(table)) RENAME TO \(quote(newName))"
    }

    func addColumnSQL(_ table: TableRef, column: ColumnDefinition) -> String {
        "ALTER TABLE \(qualifiedName(table)) ADD COLUMN \(columnClause(column))"
    }

    func dropColumnSQL(_ table: TableRef, column: String) -> String {
        "ALTER TABLE \(qualifiedName(table)) DROP COLUMN \(quote(column))"
    }

    /// Pure column rename via `RENAME COLUMN` for both dialects. Unlike MySQL's
    /// `CHANGE COLUMN`, this does not restate the column definition, so it can't
    /// accidentally drop `NOT NULL` / `AUTO_INCREMENT` / length on a rename — but
    /// it requires MySQL 8.0.1+ or MariaDB 10.5.2+ (both current GA releases).
    func renameColumnSQL(_ table: TableRef, column: String, to newName: String) -> String {
        "ALTER TABLE \(qualifiedName(table)) RENAME COLUMN \(quote(column)) TO \(quote(newName))"
    }

    /// `"name" type [NOT NULL] [DEFAULT expr]` for one column.
    func columnClause(_ column: ColumnDefinition) -> String {
        var clause = "\(quote(column.name)) \(column.type)"
        if !column.isNullable { clause += " NOT NULL" }
        if let def = column.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines), !def.isEmpty {
            clause += " DEFAULT \(def)"
        }
        return clause
    }
}
