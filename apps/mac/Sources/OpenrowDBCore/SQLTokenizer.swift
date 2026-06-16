// SQLTokenizer.swift
import Foundation

/// What a `SQLToken` represents. The tokenizer never returns `.identifier` for
/// a name that's also a keyword/function — those win.
public enum SQLTokenKind: Sendable, Equatable, Hashable {
    case keyword
    case function
    case identifier
    case quotedIdentifier
    case stringLiteral
    case numberLiteral
    case lineComment
    case blockComment
    case `operator`
    case punctuation
    case whitespace
}

/// A single lexed span. `range` is in **UTF-16 code units** so callers can hand
/// it directly to `NSAttributedString` / `NSLayoutManager.addTemporaryAttribute`
/// without a second pass.
public struct SQLToken: Sendable, Equatable, Hashable {
    public let kind: SQLTokenKind
    public let range: NSRange

    public init(kind: SQLTokenKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// Pure, allocation-light SQL lexer used by the syntax highlighter.
///
/// Design choices that affect correctness:
/// 1. Operates on a `[Character]` snapshot once, then converts spans to UTF-16
///    ranges at emit time. Mixing UTF-8 / Swift `String.Index` / NSRange in a
///    hot loop is the classic source of off-by-one highlighter bugs.
/// 2. Numbers accept `1`, `1.5`, `.5`, `1e10`, `1.5E-3` — the SQL standard
///    superset. Trailing `.` (e.g. `1.foo`) is left as `1` + `.` + `foo`.
/// 3. Strings recognize SQL escape `''` (double single quote = literal `'`).
///    Backslash escapes are NOT honored — that's a MySQL extension off by
///    default in modern versions and would mis-tokenize standard Postgres.
/// 4. Function vs keyword: a name token is `.function` iff the next non-space
///    character is `(` AND the name appears in `dialect.functions`. Otherwise
///    it falls back to `.keyword` (if in `dialect.keywords`) or `.identifier`.
public enum SQLTokenizer {

    public static func tokenize(_ text: String, dialect: SQLDialect) -> [SQLToken] {
        let chars = Array(text)
        var tokens: [SQLToken] = []
        tokens.reserveCapacity(chars.count / 4)

        let keywordSet = Set(dialect.keywords)
        let functionSet = Set(dialect.functions)

        var i = 0
        var utf16Offset = 0

        while i < chars.count {
            let start = i
            let startUtf16 = utf16Offset
            let c = chars[i]

            if c == "-", i + 1 < chars.count, chars[i + 1] == "-" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                let span = String(chars[start..<i])
                let len = span.utf16.count
                tokens.append(SQLToken(kind: .lineComment, range: NSRange(location: startUtf16, length: len)))
                utf16Offset += len
                continue
            }

            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i < chars.count {
                    if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" {
                        i += 2
                        break
                    }
                    i += 1
                }
                let span = String(chars[start..<i])
                let len = span.utf16.count
                tokens.append(SQLToken(kind: .blockComment, range: NSRange(location: startUtf16, length: len)))
                utf16Offset += len
                continue
            }

            if c == "'" {
                i += 1
                while i < chars.count {
                    if chars[i] == "'" {
                        if i + 1 < chars.count, chars[i + 1] == "'" {
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                let span = String(chars[start..<i])
                let len = span.utf16.count
                tokens.append(SQLToken(kind: .stringLiteral, range: NSRange(location: startUtf16, length: len)))
                utf16Offset += len
                continue
            }

            if c == "\"" || c == "`" {
                let closer = c
                i += 1
                while i < chars.count {
                    if chars[i] == closer {
                        if i + 1 < chars.count, chars[i + 1] == closer {
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                let span = String(chars[start..<i])
                let len = span.utf16.count
                tokens.append(SQLToken(kind: .quotedIdentifier, range: NSRange(location: startUtf16, length: len)))
                utf16Offset += len
                continue
            }

            if c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isNumber) {
                while i < chars.count, chars[i].isNumber { i += 1 }
                if i < chars.count, chars[i] == ".", i + 1 < chars.count, chars[i + 1].isNumber {
                    i += 1
                    while i < chars.count, chars[i].isNumber { i += 1 }
                }
                if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                    var probe = i + 1
                    if probe < chars.count, chars[probe] == "+" || chars[probe] == "-" { probe += 1 }
                    if probe < chars.count, chars[probe].isNumber {
                        i = probe
                        while i < chars.count, chars[i].isNumber { i += 1 }
                    }
                }
                let span = String(chars[start..<i])
                let len = span.utf16.count
                tokens.append(SQLToken(kind: .numberLiteral, range: NSRange(location: startUtf16, length: len)))
                utf16Offset += len
                continue
            }

            if c.isLetter || c == "_" {
                while i < chars.count, chars[i].isLetter || chars[i].isNumber || chars[i] == "_" {
                    i += 1
                }
                let span = String(chars[start..<i])
                let len = span.utf16.count
                let upper = span.uppercased()

                var lookahead = i
                while lookahead < chars.count, chars[lookahead].isWhitespace { lookahead += 1 }
                let followedByParen = lookahead < chars.count && chars[lookahead] == "("

                let kind: SQLTokenKind
                if followedByParen, functionSet.contains(upper) {
                    kind = .function
                } else if keywordSet.contains(upper) {
                    kind = .keyword
                } else {
                    kind = .identifier
                }
                tokens.append(SQLToken(kind: kind, range: NSRange(location: startUtf16, length: len)))
                utf16Offset += len
                continue
            }

            if c.isWhitespace {
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                let span = String(chars[start..<i])
                let len = span.utf16.count
                tokens.append(SQLToken(kind: .whitespace, range: NSRange(location: startUtf16, length: len)))
                utf16Offset += len
                continue
            }

            let len = String(c).utf16.count
            let kind: SQLTokenKind = "()[],;.".contains(c) ? .punctuation : .operator
            tokens.append(SQLToken(kind: kind, range: NSRange(location: startUtf16, length: len)))
            i += 1
            utf16Offset += len
        }

        return tokens
    }
}
