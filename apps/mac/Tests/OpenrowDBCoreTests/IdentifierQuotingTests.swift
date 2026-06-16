// IdentifierQuotingTests.swift
import XCTest
@testable import OpenrowDBCore

final class IdentifierQuotingTests: XCTestCase {
    func testPostgresSimpleIdentifier() {
        XCTAssertEqual(SQLDialect.postgres.quoteQualified("Seat"), "\"Seat\"")
    }

    func testPostgresSchemaQualified() {
        XCTAssertEqual(SQLDialect.postgres.quoteQualified("public.Seat"), "\"public\".\"Seat\"")
    }

    func testPostgresEscapesEmbeddedQuote() {
        XCTAssertEqual(SQLDialect.postgres.quoteQualified("foo\"bar"), "\"foo\"\"bar\"")
    }

    func testPostgresPreservesAlreadyQuoted() {
        XCTAssertEqual(SQLDialect.postgres.quoteQualified("\"My Schema\".tbl"), "\"My Schema\".\"tbl\"")
    }

    func testPostgresDotInsideQuotesIsNotASplit() {
        XCTAssertEqual(SQLDialect.postgres.quoteQualified("\"a.b\".c"), "\"a.b\".\"c\"")
    }

    func testMysqlSimpleIdentifier() {
        XCTAssertEqual(SQLDialect.mysql.quoteQualified("Seat"), "`Seat`")
    }

    func testMysqlSchemaQualified() {
        XCTAssertEqual(SQLDialect.mysql.quoteQualified("public.Seat"), "`public`.`Seat`")
    }

    func testMysqlEscapesEmbeddedBacktick() {
        XCTAssertEqual(SQLDialect.mysql.quoteQualified("foo`bar"), "`foo``bar`")
    }

    func testMysqlPreservesAlreadyQuoted() {
        XCTAssertEqual(SQLDialect.mysql.quoteQualified("`My DB`.tbl"), "`My DB`.`tbl`")
    }

    func testEmptyStringPassesThrough() {
        XCTAssertEqual(SQLDialect.postgres.quoteQualified(""), "")
        XCTAssertEqual(SQLDialect.mysql.quoteQualified(""), "")
    }

    func testPostgresThreeSegments() {
        XCTAssertEqual(SQLDialect.postgres.quoteQualified("db.public.Seat"), "\"db\".\"public\".\"Seat\"")
    }
}
