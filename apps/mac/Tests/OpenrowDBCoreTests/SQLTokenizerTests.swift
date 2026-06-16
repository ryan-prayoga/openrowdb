// SQLTokenizerTests.swift
import XCTest
@testable import OpenrowDBCore

final class SQLTokenizerTests: XCTestCase {

    private func tokens(_ text: String, dialect: SQLDialect = .postgres) -> [SQLToken] {
        SQLTokenizer.tokenize(text, dialect: dialect)
            .filter { $0.kind != .whitespace }
    }

    func testKeywordSelect() {
        let t = tokens("SELECT")
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].kind, .keyword)
    }

    func testKeywordCaseInsensitive() {
        XCTAssertEqual(tokens("select")[0].kind, .keyword)
        XCTAssertEqual(tokens("SeLeCt")[0].kind, .keyword)
    }

    func testFunctionRequiresParen() {
        let t = tokens("COUNT(*)")
        XCTAssertEqual(t[0].kind, .function)
        XCTAssertEqual(t[0].range, NSRange(location: 0, length: 5))
    }

    func testFunctionWithSpaceBeforeParen() {
        let t = tokens("COUNT (*)")
        XCTAssertEqual(t[0].kind, .function, "Whitespace between name and `(` should still classify as function")
    }

    func testNameWithoutParenIsIdentifier() {
        let t = tokens("SELECT count FROM t")
        let countTok = t.first { tok in
            (tok.range.location..<NSMaxRange(tok.range)).contains(7)
        }
        XCTAssertEqual(countTok?.kind, .identifier, "`count` without `(` is a column name, not a function")
    }

    func testLeftAsKeywordInJoin() {
        let t = tokens("LEFT JOIN x")
        XCTAssertEqual(t[0].kind, .keyword)
    }

    func testLeftAsFunctionWithParen() {
        let t = tokens("LEFT('hi', 1)")
        XCTAssertEqual(t[0].kind, .function)
    }

    func testStringLiteralBasic() {
        let t = tokens("'hello'")
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].kind, .stringLiteral)
        XCTAssertEqual(t[0].range, NSRange(location: 0, length: 7))
    }

    func testStringLiteralWithEscapedQuote() {
        let t = tokens("'it''s'")
        XCTAssertEqual(t.count, 1)
        XCTAssertEqual(t[0].kind, .stringLiteral)
        XCTAssertEqual(t[0].range.length, 7)
    }

    func testUnterminatedStringRunsToEnd() {
        let t = tokens("'oops")
        XCTAssertEqual(t[0].kind, .stringLiteral)
    }

    func testQuotedIdentifierPostgres() {
        let t = tokens("\"Seat\"", dialect: .postgres)
        XCTAssertEqual(t[0].kind, .quotedIdentifier)
    }

    func testQuotedIdentifierMysql() {
        let t = tokens("`Seat`", dialect: .mysql)
        XCTAssertEqual(t[0].kind, .quotedIdentifier)
    }

    func testNumberInteger() {
        let t = tokens("42")
        XCTAssertEqual(t[0].kind, .numberLiteral)
        XCTAssertEqual(t[0].range.length, 2)
    }

    func testNumberDecimal() {
        let t = tokens("3.14")
        XCTAssertEqual(t[0].kind, .numberLiteral)
        XCTAssertEqual(t[0].range.length, 4)
    }

    func testNumberLeadingDot() {
        let t = tokens(".5")
        XCTAssertEqual(t[0].kind, .numberLiteral)
        XCTAssertEqual(t[0].range.length, 2)
    }

    func testNumberScientific() {
        let t = tokens("1e10")
        XCTAssertEqual(t[0].kind, .numberLiteral)
        XCTAssertEqual(t[0].range.length, 4)
    }

    func testNumberScientificNegativeExponent() {
        let t = tokens("1.5E-3")
        XCTAssertEqual(t[0].kind, .numberLiteral)
        XCTAssertEqual(t[0].range.length, 6)
    }

    func testLineComment() {
        let t = tokens("-- hello\nSELECT")
        XCTAssertEqual(t[0].kind, .lineComment)
        XCTAssertEqual(t[1].kind, .keyword)
    }

    func testBlockComment() {
        let t = tokens("/* a */ SELECT")
        XCTAssertEqual(t[0].kind, .blockComment)
        XCTAssertEqual(t[1].kind, .keyword)
    }

    func testUnterminatedBlockCommentRunsToEnd() {
        let t = tokens("/* never closed")
        XCTAssertEqual(t[0].kind, .blockComment)
    }

    func testNumberBeforeDotIsNotConsumedAsDecimal() {
        let t = tokens("1.foo")
        XCTAssertEqual(t[0].kind, .numberLiteral)
        XCTAssertEqual(t[0].range.length, 1, "`1` then `.` then `foo` — no decimal because `f` isn't a digit")
        XCTAssertEqual(t[1].kind, .punctuation)
        XCTAssertEqual(t[2].kind, .identifier)
    }

    func testFullSelectStatement() {
        let t = tokens("SELECT id, name FROM users WHERE id = 1")
        let kinds = t.map(\.kind)
        XCTAssertEqual(kinds, [
            .keyword,        // SELECT
            .identifier,     // id
            .punctuation,    // ,
            .identifier,     // name
            .keyword,        // FROM
            .identifier,     // users
            .keyword,        // WHERE
            .identifier,     // id
            .operator,       // =
            .numberLiteral   // 1
        ])
    }

    func testRangesCoverFullText() {
        let text = "SELECT 1"
        let all = SQLTokenizer.tokenize(text, dialect: .postgres)
        let totalLen = all.map(\.range.length).reduce(0, +)
        XCTAssertEqual(totalLen, (text as NSString).length)
    }

    func testEmptyString() {
        XCTAssertTrue(SQLTokenizer.tokenize("", dialect: .postgres).isEmpty)
    }
}
