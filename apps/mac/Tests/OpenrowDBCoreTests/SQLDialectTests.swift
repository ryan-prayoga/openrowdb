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

    func testSelectRowsWithSortAscending() {
        let table = TableRef(schema: "public", name: "Movie")
        let sql = SQLDialect.postgres.selectRowsSQL(table, limit: 50, offset: 0, sort: SortSpec(column: "title", ascending: true))
        XCTAssertEqual(sql, "SELECT * FROM \"public\".\"Movie\" ORDER BY \"title\" ASC LIMIT 50 OFFSET 0")
    }

    func testSelectRowsWithSortDescendingQuotesColumn() {
        let table = TableRef(schema: "s", name: "t")
        let sql = SQLDialect.mysql.selectRowsSQL(table, limit: 10, offset: 5, sort: SortSpec(column: "we`ird", ascending: false))
        XCTAssertEqual(sql, "SELECT * FROM `s`.`t` ORDER BY `we``ird` DESC LIMIT 10 OFFSET 5")
    }

    func testCountRowsSQL() {
        let table = TableRef(schema: "public", name: "Seat")
        XCTAssertEqual(SQLDialect.postgres.countRowsSQL(table), "SELECT COUNT(*) FROM \"public\".\"Seat\"")
        XCTAssertEqual(SQLDialect.mysql.countRowsSQL(TableRef(schema: "s", name: "t")), "SELECT COUNT(*) FROM `s`.`t`")
    }

    func testDriverMapsToDialect() {
        XCTAssertEqual(Connection.Driver.postgres.dialect, .postgres)
        XCTAssertEqual(Connection.Driver.mysql.dialect, .mysql)
    }

    func testQuoteLiteralEscapesSingleQuotes() {
        XCTAssertEqual(SQLDialect.postgres.quoteLiteral("O'Brien"), "'O''Brien'")
    }

    func testListTablesIncludesViews() {
        XCTAssertTrue(SQLDialect.postgres.listTablesSQL.contains("'VIEW'"))
        XCTAssertTrue(SQLDialect.postgres.listTablesSQL.contains("table_type"))
    }

    func testListColumnsSQLUsesLiterals() {
        let sql = SQLDialect.postgres.listColumnsSQL(TableRef(schema: "public", name: "Movie"))
        XCTAssertTrue(sql.contains("information_schema.columns"))
        XCTAssertTrue(sql.contains("table_schema = 'public'"))
        XCTAssertTrue(sql.contains("table_name = 'Movie'"))
        XCTAssertTrue(sql.contains("ORDER BY ordinal_position"))
    }

    func testEstimatedRowCountSQLPostgresUsesRegclass() {
        let sql = SQLDialect.postgres.estimatedRowCountSQL(TableRef(schema: "public", name: "Seat"))
        XCTAssertEqual(sql, "SELECT reltuples::bigint FROM pg_class WHERE oid = '\"public\".\"Seat\"'::regclass")
    }

    func testEstimatedRowCountSQLMySQLUsesInformationSchema() {
        let sql = SQLDialect.mysql.estimatedRowCountSQL(TableRef(schema: "shop", name: "orders"))
        XCTAssertTrue(sql.contains("table_rows"))
        XCTAssertTrue(sql.contains("table_schema = 'shop'"))
        XCTAssertTrue(sql.contains("table_name = 'orders'"))
    }
}
