// SQLStatementSplitterTests.swift
import XCTest
@testable import OpenrowDBCore

final class SQLStatementSplitterTests: XCTestCase {
    func testEmptyInputReturnsEmptyArray() {
        XCTAssertEqual(SQLStatementSplitter.split(""), [])
        XCTAssertEqual(SQLStatementSplitter.split("   \n\t  "), [])
        XCTAssertEqual(SQLStatementSplitter.split(";"), [])
        XCTAssertEqual(SQLStatementSplitter.split(";;;"), [])
    }

    func testSingleStatementWithoutTrailingSemicolon() {
        XCTAssertEqual(SQLStatementSplitter.split("SELECT 1"), ["SELECT 1"])
    }

    func testSingleStatementWithTrailingSemicolon() {
        XCTAssertEqual(SQLStatementSplitter.split("SELECT 1;"), ["SELECT 1"])
    }

    func testTwoSimpleStatements() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT 1; SELECT 2;"),
            ["SELECT 1", "SELECT 2"]
        )
    }

    func testTrimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(
            SQLStatementSplitter.split("\n  SELECT 1  ;\n\n  SELECT 2  \n"),
            ["SELECT 1", "SELECT 2"]
        )
    }

    func testSkipsSemicolonInsideSingleQuotedString() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT 'a;b;c'; SELECT 2"),
            ["SELECT 'a;b;c'", "SELECT 2"]
        )
    }

    func testHandlesEscapedSingleQuoteInsideString() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT 'O''Brien; Jr'; SELECT 2"),
            ["SELECT 'O''Brien; Jr'", "SELECT 2"]
        )
    }

    func testSkipsSemicolonInsideDoubleQuotedIdentifier() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT \"weird;col\" FROM t; SELECT 2"),
            ["SELECT \"weird;col\" FROM t", "SELECT 2"]
        )
    }

    func testSkipsSemicolonInsideBacktickIdentifier() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT `weird;col` FROM t; SELECT 2"),
            ["SELECT `weird;col` FROM t", "SELECT 2"]
        )
    }

    func testHandlesEscapedDoubleQuoteInsideIdentifier() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT \"a\"\"b;c\" ; SELECT 2"),
            ["SELECT \"a\"\"b;c\"", "SELECT 2"]
        )
    }

    func testSkipsSemicolonInLineComment() {
        let sql = "SELECT 1 -- ignored ; here\n; SELECT 2"
        XCTAssertEqual(
            SQLStatementSplitter.split(sql),
            ["SELECT 1 -- ignored ; here", "SELECT 2"]
        )
    }

    func testSkipsSemicolonInBlockComment() {
        let sql = "SELECT 1 /* ignore ; this */; SELECT 2"
        XCTAssertEqual(
            SQLStatementSplitter.split(sql),
            ["SELECT 1 /* ignore ; this */", "SELECT 2"]
        )
    }

    func testHandlesMultilineBlockComment() {
        let sql = "SELECT 1 /* line1\n;line2\nline3 */; SELECT 2"
        XCTAssertEqual(
            SQLStatementSplitter.split(sql),
            ["SELECT 1 /* line1\n;line2\nline3 */", "SELECT 2"]
        )
    }

    func testCollapsesEmptyStatementsBetweenSemicolons() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT 1;;;SELECT 2;;"),
            ["SELECT 1", "SELECT 2"]
        )
    }

    func testUnterminatedStringConsumesToEnd() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT 'never closed; not a split"),
            ["SELECT 'never closed; not a split"]
        )
    }

    func testUnterminatedBlockCommentConsumesToEnd() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT 1 /* unterminated ; comment"),
            ["SELECT 1 /* unterminated ; comment"]
        )
    }

    func testMultilineRealisticDDL() {
        let sql = """
        CREATE TABLE users (
            id BIGSERIAL PRIMARY KEY,
            name TEXT NOT NULL DEFAULT 'anon;ymous',
            note TEXT
        );

        -- seed some rows
        INSERT INTO users (name, note) VALUES
            ('Alice', 'first; user'),
            ('Bob', NULL);

        SELECT * FROM users;
        """
        let result = SQLStatementSplitter.split(sql)
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result[0].hasPrefix("CREATE TABLE users"))
        XCTAssertTrue(result[0].contains("'anon;ymous'"))
        XCTAssertTrue(result[1].hasPrefix("-- seed some rows"))
        XCTAssertTrue(result[1].contains("'first; user'"))
        XCTAssertEqual(result[2], "SELECT * FROM users")
    }

    func testUnicodeIsPreserved() {
        XCTAssertEqual(
            SQLStatementSplitter.split("SELECT 'café; naïve'; SELECT '日本語;'"),
            ["SELECT 'café; naïve'", "SELECT '日本語;'"]
        )
    }
}
