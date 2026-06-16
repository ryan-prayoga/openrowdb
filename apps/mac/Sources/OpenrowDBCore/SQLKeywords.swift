// SQLKeywords.swift
import Foundation

public extension SQLDialect {
    /// Words that appear as bare clause/DML/DDL/operator tokens. These never
    /// look like function calls (they don't take an argument list in
    /// parentheses), so the syntax highlighter can color them as "keyword"
    /// without checking for a trailing `(`. Used by the autocomplete provider
    /// for `.keyword` suggestions and by the tokenizer for keyword detection.
    var keywords: [String] {
        switch self {
        case .postgres: return Self.postgresKeywords
        case .mysql: return Self.mysqlKeywords
        }
    }

    /// Words that name SQL functions (aggregate/window/string/numeric/datetime/
    /// conditional). The tokenizer classifies these as `.function` ONLY when
    /// the immediate next non-space character is `(`, so a column literally
    /// named "count" still tokenizes as `.identifier`. The completion provider
    /// surfaces these as `.function` suggestions in expression contexts.
    var functions: [String] {
        switch self {
        case .postgres: return Self.postgresFunctions
        case .mysql: return Self.mysqlFunctions
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
        "INT", "INTEGER", "BIGINT", "SMALLINT", "FLOAT", "DOUBLE", "DECIMAL", "NUMERIC",
        "VARCHAR", "TEXT", "CHAR", "BOOLEAN", "DATE", "TIME", "TIMESTAMP", "INTERVAL",
        "WITH", "RECURSIVE", "EXPLAIN", "ANALYZE", "TRUNCATE", "GRANT", "REVOKE",
        "IF", "REPLACE", "RENAME", "TO"
    ]

    /// Functions shared by both dialects: aggregate, string, numeric, conditional,
    /// datetime essentials. Functions that exist in both Postgres and MySQL but
    /// take different parameter shapes are still listed here — the tokenizer
    /// only cares about the bare name + trailing `(`.
    private static let commonFunctions: [String] = [
        // Aggregate
        "COUNT", "SUM", "AVG", "MIN", "MAX",
        // Conditional / null handling
        "COALESCE", "NULLIF", "IFNULL", "GREATEST", "LEAST", "CAST", "CONVERT",
        // String
        "CONCAT", "SUBSTR", "SUBSTRING", "LENGTH", "CHAR_LENGTH", "OCTET_LENGTH",
        "UPPER", "LOWER", "TRIM", "LTRIM", "RTRIM", "REPLACE", "REVERSE",
        "LEFT", "RIGHT", "LPAD", "RPAD", "REPEAT", "POSITION",
        // Numeric
        "ABS", "CEIL", "CEILING", "FLOOR", "ROUND", "TRUNC", "POWER", "POW",
        "SQRT", "EXP", "LN", "LOG", "LOG10", "MOD", "SIGN", "RAND", "RANDOM",
        // Datetime
        "NOW", "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP",
        "EXTRACT", "DATE_TRUNC", "DATE_PART", "DATEADD", "DATEDIFF",
        "YEAR", "MONTH", "DAY", "HOUR", "MINUTE", "SECOND",
        // Type/format
        "TO_CHAR", "TO_DATE", "TO_TIMESTAMP", "TO_NUMBER"
    ]

    private static let postgresKeywords: [String] = (commonKeywords + [
        "RETURNING", "CONFLICT", "DO", "NOTHING", "OVERLAPS",
        "JSON", "JSONB", "UUID", "BYTEA", "SERIAL", "BIGSERIAL", "TIMESTAMPTZ", "TIMETZ",
        "ARRAY", "WINDOW", "OVER", "PARTITION", "ROWS", "RANGE", "PRECEDING", "FOLLOWING",
        "LATERAL", "FILTER", "WITHIN", "GROUPING", "SETS", "CUBE", "ROLLUP",
        "MATERIALIZED", "REFRESH", "SEQUENCE", "EXTENSION",
        "TRIGGER", "LANGUAGE", "BODY", "DECLARE", "PERFORM", "RAISE", "EXCEPTION",
        "REGCLASS", "REGPROC", "TSVECTOR", "TSQUERY", "POINT", "POLYGON",
        "GENERATED", "ALWAYS", "STORED", "IDENTITY"
    ]).sorted()

    /// Postgres-specific function set on top of the common pool. Window
    /// functions, JSON/JSONB builders, regex, and array helpers live here
    /// because the tokenizer's "function = name + `(`" rule lets us color
    /// `array_agg(x)` as a function while leaving bare `ARRAY` (the type) as a
    /// keyword.
    private static let postgresFunctions: [String] = (commonFunctions + [
        // Window
        "ROW_NUMBER", "RANK", "DENSE_RANK", "NTILE", "LAG", "LEAD",
        "FIRST_VALUE", "LAST_VALUE", "NTH_VALUE", "CUME_DIST", "PERCENT_RANK",
        // Aggregate (extended)
        "STRING_AGG", "ARRAY_AGG", "JSON_AGG", "JSONB_AGG",
        "STDDEV", "VARIANCE", "BOOL_AND", "BOOL_OR", "EVERY",
        "PERCENTILE_CONT", "PERCENTILE_DISC",
        // Regex
        "REGEXP_REPLACE", "REGEXP_MATCH", "REGEXP_MATCHES", "REGEXP_SPLIT_TO_ARRAY",
        // JSON / JSONB
        "JSON_BUILD_OBJECT", "JSON_BUILD_ARRAY", "JSONB_BUILD_OBJECT", "JSONB_BUILD_ARRAY",
        "JSON_OBJECT", "JSONB_OBJECT", "JSON_EXTRACT_PATH", "JSONB_EXTRACT_PATH",
        "JSONB_SET", "JSONB_INSERT", "JSONB_PATH_QUERY", "TO_JSON", "TO_JSONB",
        // Array
        "UNNEST", "ARRAY_LENGTH", "ARRAY_POSITION", "ARRAY_REMOVE", "ARRAY_APPEND",
        "ARRAY_PREPEND", "ARRAY_CAT", "ARRAY_TO_STRING", "STRING_TO_ARRAY",
        // Datetime (extended)
        "AGE", "MAKE_DATE", "MAKE_TIMESTAMP", "JUSTIFY_DAYS", "JUSTIFY_HOURS",
        // String (extended)
        "INITCAP", "SPLIT_PART", "TRANSLATE", "FORMAT", "MD5", "ENCODE", "DECODE",
        // System
        "GEN_RANDOM_UUID", "PG_TYPEOF", "PG_RELATION_SIZE", "CURRENT_USER", "CURRENT_SCHEMA"
    ]).sorted()

    private static let mysqlKeywords: [String] = (commonKeywords + [
        "ENGINE", "INNODB", "MYISAM", "CHARSET", "COLLATE", "UTF8MB4",
        "MEDIUMINT", "TINYINT", "MEDIUMTEXT", "LONGTEXT", "BLOB", "ENUM", "SET", "JSON",
        "DATETIME", "GEOMETRY",
        "STRAIGHT_JOIN", "USE", "FORCE", "IGNORE", "DELAYED", "HIGH_PRIORITY", "LOW_PRIORITY",
        "DUPLICATE", "LOCK", "UNLOCK", "TABLES", "READ", "WRITE",
        "DESCRIBE", "SHOW", "STATUS", "VARIABLES", "PROCESSLIST",
        "UNSIGNED", "ZEROFILL", "BINARY", "VARBINARY",
        "FULLTEXT", "SPATIAL", "MATCH", "AGAINST",
        "TEMPORARY", "ALGORITHM", "DEFINER", "INVOKER", "SQL", "SECURITY"
    ]).sorted()

    /// MySQL-specific function set. Includes window functions (8.0+),
    /// MySQL-flavored string/datetime helpers, and JSON manipulators.
    private static let mysqlFunctions: [String] = (commonFunctions + [
        // Window (MySQL 8.0+)
        "ROW_NUMBER", "RANK", "DENSE_RANK", "NTILE", "LAG", "LEAD",
        "FIRST_VALUE", "LAST_VALUE", "NTH_VALUE", "CUME_DIST", "PERCENT_RANK",
        // Aggregate (extended)
        "GROUP_CONCAT", "STD", "STDDEV", "VARIANCE", "VAR_POP", "VAR_SAMP",
        "BIT_AND", "BIT_OR", "BIT_XOR",
        // String (extended)
        "FIND_IN_SET", "INSTR", "LOCATE", "MID", "SOUNDEX", "FORMAT", "ELT",
        "MAKE_SET", "QUOTE", "EXPORT_SET",
        // Datetime (extended)
        "DATE_ADD", "DATE_SUB", "DATE_FORMAT", "STR_TO_DATE",
        "UNIX_TIMESTAMP", "FROM_UNIXTIME", "TIMESTAMPDIFF", "TIMESTAMPADD",
        "WEEK", "WEEKDAY", "DAYOFWEEK", "DAYOFMONTH", "DAYOFYEAR", "QUARTER",
        // JSON
        "JSON_OBJECT", "JSON_ARRAY", "JSON_EXTRACT", "JSON_SET", "JSON_INSERT",
        "JSON_REPLACE", "JSON_REMOVE", "JSON_CONTAINS", "JSON_KEYS", "JSON_LENGTH",
        "JSON_MERGE", "JSON_VALID", "JSON_TYPE", "JSON_QUOTE", "JSON_UNQUOTE",
        // Numeric (extended)
        "CRC32", "CONV", "DEGREES", "RADIANS", "PI",
        // Encryption / hash
        "MD5", "SHA1", "SHA2", "AES_ENCRYPT", "AES_DECRYPT", "PASSWORD", "UUID"
    ]).sorted()
}
