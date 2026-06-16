// SQLKeywords.swift
import Foundation

public extension SQLDialect {
    var keywords: [String] {
        switch self {
        case .postgres: return Self.postgresKeywords
        case .mysql: return Self.mysqlKeywords
        }
    }

    private static let commonKeywords: [String] = [
        "SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "NULL", "IS", "IN", "BETWEEN",
        "LIKE", "ILIKE", "EXISTS", "ALL", "ANY", "SOME", "AS", "ON", "USING",
        "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "OUTER", "CROSS", "NATURAL",
        "GROUP", "BY", "HAVING", "ORDER", "ASC", "DESC", "LIMIT", "OFFSET", "DISTINCT",
        "UNION", "INTERSECT", "EXCEPT",
        "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "DATABASE", "SCHEMA",
        "ADD", "COLUMN", "CONSTRAINT", "PRIMARY", "KEY", "FOREIGN", "REFERENCES",
        "UNIQUE", "CHECK", "DEFAULT", "AUTO_INCREMENT",
        "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "SAVEPOINT",
        "TRUE", "FALSE", "CASE", "WHEN", "THEN", "ELSE", "END",
        "CAST", "COALESCE", "NULLIF",
        "COUNT", "SUM", "AVG", "MIN", "MAX",
        "INT", "INTEGER", "BIGINT", "SMALLINT", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC",
        "VARCHAR", "TEXT", "CHAR", "BOOLEAN", "DATE", "TIME", "TIMESTAMP", "INTERVAL",
        "WITH", "RECURSIVE", "EXPLAIN", "ANALYZE", "TRUNCATE", "GRANT", "REVOKE",
        "IF", "REPLACE", "RENAME", "TO"
    ]

    private static let postgresKeywords: [String] = (commonKeywords + [
        "RETURNING", "CONFLICT", "DO", "NOTHING", "OVERLAPS",
        "JSON", "JSONB", "UUID", "BYTEA", "SERIAL", "BIGSERIAL", "TIMESTAMPTZ", "TIMETZ",
        "ARRAY", "WINDOW", "OVER", "PARTITION", "ROWS", "RANGE", "PRECEDING", "FOLLOWING",
        "LATERAL", "FILTER", "WITHIN", "GROUPING", "SETS", "CUBE", "ROLLUP",
        "MATERIALIZED", "REFRESH", "SEQUENCE", "EXTENSION", "FUNCTION", "PROCEDURE",
        "TRIGGER", "LANGUAGE", "BODY", "DECLARE", "PERFORM", "RAISE", "EXCEPTION",
        "REGCLASS", "REGPROC", "TSVECTOR", "TSQUERY", "POINT", "POLYGON",
        "GENERATED", "ALWAYS", "STORED", "IDENTITY",
        "STRING_AGG", "ARRAY_AGG", "JSON_AGG", "JSONB_AGG", "REGEXP_REPLACE", "REGEXP_MATCH"
    ]).sorted()

    private static let mysqlKeywords: [String] = (commonKeywords + [
        "ENGINE", "INNODB", "MYISAM", "CHARSET", "COLLATE", "UTF8MB4",
        "MEDIUMINT", "TINYINT", "MEDIUMTEXT", "LONGTEXT", "BLOB", "ENUM", "SET", "JSON",
        "DATETIME", "YEAR", "GEOMETRY",
        "STRAIGHT_JOIN", "USE", "FORCE", "IGNORE", "DELAYED", "HIGH_PRIORITY", "LOW_PRIORITY",
        "DUPLICATE", "LOCK", "UNLOCK", "TABLES", "READ", "WRITE",
        "DESCRIBE", "DESC", "SHOW", "STATUS", "VARIABLES", "PROCESSLIST",
        "GROUP_CONCAT", "IFNULL", "FIND_IN_SET",
        "UNSIGNED", "ZEROFILL", "BINARY", "VARBINARY",
        "FULLTEXT", "SPATIAL", "MATCH", "AGAINST",
        "TEMPORARY", "ALGORITHM", "DEFINER", "INVOKER", "SQL", "SECURITY"
    ]).sorted()
}
