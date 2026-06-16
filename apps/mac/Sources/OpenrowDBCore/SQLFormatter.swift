// SQLFormatter.swift
import Foundation

/// Lightweight SQL beautifier for the editor. Not a full pretty-printer — it
/// normalizes whitespace and breaks major clauses onto their own indented lines
/// while preserving string literals, comments, and quoted identifiers verbatim.
public enum SQLFormatter {

    /// Keywords that start a new line when encountered at paren depth zero.
    /// Multi-word clauses (`ORDER BY`) are handled by peeking the next keyword.
    private static let clauseStarters: Set<String> = [
        "FROM", "WHERE", "JOIN", "INNER", "LEFT", "RIGHT", "FULL", "CROSS",
        "GROUP", "HAVING", "ORDER", "LIMIT", "OFFSET", "UNION", "INTERSECT",
        "EXCEPT", "SET", "VALUES", "ON", "INTO", "USING", "RETURNING",
    ]

    public static func format(_ sql: String, dialect: SQLDialect) -> String {
        let statements = SQLStatementSplitter.split(sql)
        guard !statements.isEmpty else { return sql }
        return statements.map { formatStatement($0, dialect: dialect) }.joined(separator: "\n\n")
    }

    private static func formatStatement(_ sql: String, dialect: SQLDialect) -> String {
        let tokens = SQLTokenizer.tokenize(sql, dialect: dialect)
        guard !tokens.isEmpty else { return sql.trimmingCharacters(in: .whitespacesAndNewlines) }

        var output = ""
        var parenDepth = 0
        var indent = 0
        var needsSpace = false
        var atLineStart = true
        var index = 0

        func appendNewline() {
            if atLineStart { return }
            output += "\n" + String(repeating: "  ", count: indent)
            needsSpace = false
            atLineStart = true
        }

        func appendText(_ text: String) {
            if needsSpace, !atLineStart, !text.hasPrefix(",") {
                output += " "
            }
            output += text
            needsSpace = false
            atLineStart = false
        }

        while index < tokens.count {
            let token = tokens[index]
            let slice = (sql as NSString).substring(with: token.range)

            switch token.kind {
            case .whitespace:
                needsSpace = !atLineStart
            case .lineComment, .blockComment:
                if !atLineStart { appendNewline() }
                appendText(slice)
                appendNewline()
            case .punctuation:
                appendText(slice)
                if slice == "(" {
                    parenDepth += 1
                    indent += 1
                } else if slice == ")" {
                    parenDepth = max(0, parenDepth - 1)
                    indent = max(0, indent - 1)
                } else if slice == "," && parenDepth == 0 {
                    appendNewline()
                }
            case .keyword:
                let upper = slice.uppercased()
                if parenDepth == 0, upper == "SELECT", atLineStart {
                    appendText(upper)
                } else if parenDepth == 0, clauseStarters.contains(upper) {
                    appendNewline()
                    if upper == "ORDER", peekKeyword(tokens, from: index + 1, sql: sql) == "BY" {
                        appendText("ORDER BY")
                        index = skipKeyword(tokens, from: index + 1, sql: sql) ?? index
                    } else if upper == "GROUP", peekKeyword(tokens, from: index + 1, sql: sql) == "BY" {
                        appendText("GROUP BY")
                        index = skipKeyword(tokens, from: index + 1, sql: sql) ?? index
                    } else if upper == "INNER", peekKeyword(tokens, from: index + 1, sql: sql) == "JOIN" {
                        appendText("INNER JOIN")
                        index = skipKeyword(tokens, from: index + 1, sql: sql) ?? index
                    } else if upper == "LEFT", peekKeyword(tokens, from: index + 1, sql: sql) == "JOIN" {
                        appendText("LEFT JOIN")
                        index = skipKeyword(tokens, from: index + 1, sql: sql) ?? index
                    } else if upper == "RIGHT", peekKeyword(tokens, from: index + 1, sql: sql) == "JOIN" {
                        appendText("RIGHT JOIN")
                        index = skipKeyword(tokens, from: index + 1, sql: sql) ?? index
                    } else if upper == "FULL", peekKeyword(tokens, from: index + 1, sql: sql) == "JOIN" {
                        appendText("FULL JOIN")
                        index = skipKeyword(tokens, from: index + 1, sql: sql) ?? index
                    } else if upper == "CROSS", peekKeyword(tokens, from: index + 1, sql: sql) == "JOIN" {
                        appendText("CROSS JOIN")
                        index = skipKeyword(tokens, from: index + 1, sql: sql) ?? index
                    } else {
                        appendText(upper)
                    }
                } else if parenDepth == 0, upper == "SELECT", !atLineStart {
                    appendNewline()
                    appendText(upper)
                } else {
                    appendText(slice)
                }
            default:
                appendText(slice)
            }

            index += 1
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func peekKeyword(_ tokens: [SQLToken], from index: Int, sql: String) -> String? {
        var i = index
        while i < tokens.count {
            switch tokens[i].kind {
            case .whitespace:
                i += 1
            case .keyword:
                return (sql as NSString).substring(with: tokens[i].range).uppercased()
            default:
                return nil
            }
        }
        return nil
    }

    private static func skipKeyword(_ tokens: [SQLToken], from index: Int, sql: String) -> Int? {
        var i = index
        while i < tokens.count {
            switch tokens[i].kind {
            case .whitespace:
                i += 1
            case .keyword:
                return i
            default:
                return nil
            }
        }
        return nil
    }
}