// SQLDialectTests.swift
import XCTest
@testable import OpenrowDBCore

final class SQLDialectTests: XCTestCase {
    func testPostgresQuotesWithDoubleQuotes() {
        XCTAssertEqual(SQLDialect.postgres.quote("users"), "\"users\"")
    }

    func testMySQLQuotesWithBackticks() {
        XCTAssertEqual(SQLDialect.mysql.quote("users"), "`users`")
    }

    func testPostgresEscapesEmbeddedDoubleQuote() {
        XCTAssertEqual(SQLDialect.postgres.quote("we\"ird"), "\"we\"\"ird\"")
    }

    func testMySQLEscapesEmbeddedBacktick() {
        XCTAssertEqual(SQLDialect.mysql.quote("we`ird"), "`we``ird`")
    }

    func testQualifiedName() {
        let table = TableRef(schema: "public", name: "orders")
        XCTAssertEqual(SQLDialect.postgres.qualifiedName(table), "\"public\".\"orders\"")
    }

    func testSelectRowsInlinesClampedIntegers() {
        let table = TableRef(schema: "public", name: "orders")
        let sql = SQLDialect.postgres.selectRowsSQL(table, limit: 100, offset: 200)
        XCTAssertEqual(sql, "SELECT * FROM \"public\".\"orders\" LIMIT 100 OFFSET 200")
    }

    func testSelectRowsClampsNegatives() {
        let table = TableRef(schema: "s", name: "t")
        let sql = SQLDialect.mysql.selectRowsSQL(table, limit: -5, offset: -9)
        XCTAssertEqual(sql, "SELECT * FROM `s`.`t` LIMIT 0 OFFSET 0")
    }

    func testDriverMapsToDialect() {
        XCTAssertEqual(Connection.Driver.postgres.dialect, .postgres)
        XCTAssertEqual(Connection.Driver.mysql.dialect, .mysql)
    }
}
