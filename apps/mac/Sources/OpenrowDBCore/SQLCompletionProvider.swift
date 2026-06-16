// SQLCompletionProvider.swift
import Foundation

public struct CompletionSuggestion: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        case keyword
        case function
        case table
        case column
        case schema
    }

    public let text: String
    public let kind: Kind
    public let detail: String?

    public init(text: String, kind: Kind, detail: String? = nil) {
        self.text = text
        self.kind = kind
        self.detail = detail
    }
}

public struct CompletionRequest: Sendable, Equatable {
    public let text: String
    public let cursor: Int
    public let dialect: SQLDialect

    public init(text: String, cursor: Int, dialect: SQLDialect) {
        self.text = text
        self.cursor = cursor
        self.dialect = dialect
    }
}

public enum SQLCompletionProvider {

    public static func suggestions(
        for request: CompletionRequest,
        schema: SchemaSnapshot
    ) -> [CompletionSuggestion] {
        let cursor = clampedCursor(in: request.text, cursor: request.cursor)
        if isInsideStringLiteralOrComment(text: request.text, cursor: cursor) {
            return []
        }

        let (prefix, replaceStart) = currentWord(in: request.text, cursor: cursor)
        let dotContext = tableQualifier(in: request.text, replaceStart: replaceStart)

        if let qualifier = dotContext {
            return columnSuggestions(prefix: prefix, qualifier: qualifier, schema: schema)
        }

        let previousKeyword = priorKeyword(in: request.text, before: replaceStart)
        if let kw = previousKeyword, ["FROM", "JOIN", "INTO", "UPDATE", "TABLE"].contains(kw) {
            // Object-position: tables first, no functions (table-valued funcs are rare).
            return tableSuggestions(prefix: prefix, schema: schema)
                + keywordSuggestions(prefix: prefix, dialect: request.dialect)
        }

        return keywordSuggestions(prefix: prefix, dialect: request.dialect)
            + functionSuggestions(prefix: prefix, dialect: request.dialect)
            + tableSuggestions(prefix: prefix, schema: schema)
    }

    private static func clampedCursor(in text: String, cursor: Int) -> Int {
        max(0, min(cursor, text.utf16.count))
    }

    private static func currentWord(in text: String, cursor: Int) -> (prefix: String, start: Int) {
        let chars = Array(text)
        guard cursor <= chars.count else { return ("", cursor) }
        var start = cursor
        while start > 0, isIdentifierChar(chars[start - 1]) {
            start -= 1
        }
        let prefix = String(chars[start..<cursor])
        return (prefix, start)
    }

    private static func tableQualifier(in text: String, replaceStart: Int) -> String? {
        let chars = Array(text)
        guard replaceStart > 0, replaceStart <= chars.count else { return nil }
        guard chars[replaceStart - 1] == "." else { return nil }
        let end = replaceStart - 1
        var start = end
        while start > 0, isIdentifierChar(chars[start - 1]) {
            start -= 1
        }
        guard start < end else { return nil }
        return String(chars[start..<end])
    }

    private static func priorKeyword(in text: String, before index: Int) -> String? {
        let chars = Array(text)
        var i = min(index, chars.count) - 1
        while i >= 0, chars[i].isWhitespace || chars[i] == "," {
            i -= 1
        }
        while i >= 0, isIdentifierChar(chars[i]) || chars[i] == "." {
            i -= 1
        }
        let start = i + 1
        var end = start
        while end < chars.count, isIdentifierChar(chars[end]) {
            end += 1
        }
        guard start < end else { return nil }
        return String(chars[start..<end]).uppercased()
    }

    private static func isIdentifierChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    private static func isInsideStringLiteralOrComment(text: String, cursor: Int) -> Bool {
        let chars = Array(text.prefix(cursor))
        var inSingle = false
        var inDouble = false
        var inLineComment = false
        var inBlockComment = false
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inLineComment {
                if c == "\n" { inLineComment = false }
                i += 1
                continue
            }
            if inBlockComment {
                if c == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                    inBlockComment = false
                    i += 2
                    continue
                }
                i += 1
                continue
            }
            if inSingle {
                if c == "'" {
                    if i + 1 < chars.count, chars[i + 1] == "'" { i += 2; continue }
                    inSingle = false
                }
                i += 1
                continue
            }
            if inDouble {
                if c == "\"" { inDouble = false }
                i += 1
                continue
            }
            if c == "-", i + 1 < chars.count, chars[i + 1] == "-" {
                inLineComment = true
                i += 2
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                inBlockComment = true
                i += 2
                continue
            }
            if c == "'" { inSingle = true; i += 1; continue }
            if c == "\"" { inDouble = true; i += 1; continue }
            i += 1
        }
        return inSingle || inLineComment || inBlockComment
    }

    private static func keywordSuggestions(prefix: String, dialect: SQLDialect) -> [CompletionSuggestion] {
        let upper = prefix.uppercased()
        let matching = dialect.keywords.filter { upper.isEmpty || $0.hasPrefix(upper) }
        return matching.map { CompletionSuggestion(text: $0, kind: .keyword, detail: nil) }
    }

    private static func functionSuggestions(prefix: String, dialect: SQLDialect) -> [CompletionSuggestion] {
        let upper = prefix.uppercased()
        let matching = dialect.functions.filter { upper.isEmpty || $0.hasPrefix(upper) }
        return matching.map { CompletionSuggestion(text: $0, kind: .function, detail: "function") }
    }

    private static func tableSuggestions(prefix: String, schema: SchemaSnapshot) -> [CompletionSuggestion] {
        let lower = prefix.lowercased()
        return schema.tables
            .filter { lower.isEmpty || $0.name.lowercased().hasPrefix(lower) }
            .map { CompletionSuggestion(text: $0.name, kind: .table, detail: $0.schema) }
    }

    private static func columnSuggestions(
        prefix: String,
        qualifier: String,
        schema: SchemaSnapshot
    ) -> [CompletionSuggestion] {
        let matches = schema.tables(named: qualifier)
        let lower = prefix.lowercased()
        var seen = Set<String>()
        var result: [CompletionSuggestion] = []
        for table in matches {
            for col in schema.columns(of: table) {
                if !lower.isEmpty, !col.name.lowercased().hasPrefix(lower) { continue }
                guard seen.insert(col.name).inserted else { continue }
                result.append(CompletionSuggestion(text: col.name, kind: .column, detail: col.type))
            }
        }
        return result
    }
}
