// SQLStatementSplitter.swift
import Foundation

/// Splits a multi-statement SQL string into individual statements on `;`,
/// skipping semicolons that live inside:
///   - single-quoted string literals       'it''s fine; really'
///   - double-quoted identifiers (Postgres) "weird;name"
///   - backtick identifiers (MySQL)         `weird;name`
///   - line comments                        -- ignore ; here
///   - block comments                       /* ignore ; here */
///
/// Trims leading/trailing whitespace+newlines from each returned statement and
/// drops empty statements (e.g. between `;;`).
///
/// v1 scope: does NOT handle Postgres dollar-quoted strings ($tag$ ... $tag$),
/// MySQL `DELIMITER` directives, or nested block comments. Those are post-v1.
public enum SQLStatementSplitter: Sendable {
    public static func split(_ sql: String) -> [String] {
        var statements: [String] = []
        var current = ""
        let scalars = Array(sql.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]

            switch scalar {
            case "'":
                current.unicodeScalars.append(scalar)
                index = consumeSingleQuotedString(scalars, from: index + 1, into: &current)

            case "\"":
                current.unicodeScalars.append(scalar)
                index = consumeDelimited(scalars, from: index + 1, terminator: "\"", into: &current)

            case "`":
                current.unicodeScalars.append(scalar)
                index = consumeDelimited(scalars, from: index + 1, terminator: "`", into: &current)

            case "-" where index + 1 < scalars.count && scalars[index + 1] == "-":
                current.unicodeScalars.append("-")
                current.unicodeScalars.append("-")
                index = consumeLineComment(scalars, from: index + 2, into: &current)

            case "/" where index + 1 < scalars.count && scalars[index + 1] == "*":
                current.unicodeScalars.append("/")
                current.unicodeScalars.append("*")
                index = consumeBlockComment(scalars, from: index + 2, into: &current)

            case ";":
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { statements.append(trimmed) }
                current.removeAll(keepingCapacity: true)
                index += 1

            default:
                current.unicodeScalars.append(scalar)
                index += 1
            }
        }

        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty { statements.append(trailing) }
        return statements
    }

    /// Consume to and including the closing single quote, treating `''` as an
    /// escaped quote that stays inside the string.
    private static func consumeSingleQuotedString(
        _ scalars: [Unicode.Scalar],
        from start: Int,
        into out: inout String
    ) -> Int {
        var i = start
        while i < scalars.count {
            let s = scalars[i]
            out.unicodeScalars.append(s)
            if s == "'" {
                if i + 1 < scalars.count && scalars[i + 1] == "'" {
                    out.unicodeScalars.append("'")
                    i += 2
                    continue
                }
                return i + 1
            }
            i += 1
        }
        return i
    }

    /// Consume to and including the next `terminator`. Doubled terminator is
    /// treated as an escape (Postgres `""`, MySQL ` `` `) and passed through.
    private static func consumeDelimited(
        _ scalars: [Unicode.Scalar],
        from start: Int,
        terminator: Unicode.Scalar,
        into out: inout String
    ) -> Int {
        var i = start
        while i < scalars.count {
            let s = scalars[i]
            out.unicodeScalars.append(s)
            if s == terminator {
                if i + 1 < scalars.count && scalars[i + 1] == terminator {
                    out.unicodeScalars.append(terminator)
                    i += 2
                    continue
                }
                return i + 1
            }
            i += 1
        }
        return i
    }

    /// Consume to end of line (or end of input), inclusive of the newline.
    private static func consumeLineComment(
        _ scalars: [Unicode.Scalar],
        from start: Int,
        into out: inout String
    ) -> Int {
        var i = start
        while i < scalars.count {
            let s = scalars[i]
            out.unicodeScalars.append(s)
            i += 1
            if s == "\n" { return i }
        }
        return i
    }

    /// Consume to and including the next `*/`. Nesting is not supported.
    private static func consumeBlockComment(
        _ scalars: [Unicode.Scalar],
        from start: Int,
        into out: inout String
    ) -> Int {
        var i = start
        while i < scalars.count {
            let s = scalars[i]
            out.unicodeScalars.append(s)
            if s == "*", i + 1 < scalars.count, scalars[i + 1] == "/" {
                out.unicodeScalars.append("/")
                return i + 2
            }
            i += 1
        }
        return i
    }
}
