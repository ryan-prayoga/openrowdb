// SQLCompletionProviderTests.swift
import XCTest
@testable import OpenrowDBCore

final class SQLCompletionProviderTests: XCTestCase {
    private let usersTable = TableRef(schema: "public", name: "users")
    private let ordersTable = TableRef(schema: "public", name: "orders")

    private var schema: SchemaSnapshot {
        SchemaSnapshot(
            tables: [usersTable, ordersTable],
            columnsByTable: [
                usersTable.id: [
                    ColumnInfo(name: "id", type: "integer"),
                    ColumnInfo(name: "email", type: "text"),
                    ColumnInfo(name: "name", type: "text")
                ],
                ordersTable.id: [
                    ColumnInfo(name: "id", type: "integer"),
                    ColumnInfo(name: "user_id", type: "integer"),
                    ColumnInfo(name: "total", type: "numeric")
                ]
            ]
        )
    }

    private func suggestions(_ text: String, cursor: Int? = nil, dialect: SQLDialect = .postgres) -> [CompletionSuggestion] {
        let c = cursor ?? text.count
        let req = CompletionRequest(text: text, cursor: c, dialect: dialect)
        return SQLCompletionProvider.suggestions(for: req, schema: schema)
    }

    func testKeywordPrefixSelect() {
        let results = suggestions("SEL")
        let texts = results.map(\.text)
        XCTAssertTrue(texts.contains("SELECT"))
        XCTAssertTrue(results.allSatisfy { $0.text.hasPrefix("SEL") })
    }

    func testTableAfterFrom() {
        let results = suggestions("SELECT * FROM us")
        let names = results.filter { $0.kind == .table }.map(\.text)
        XCTAssertTrue(names.contains("users"))
        XCTAssertFalse(names.contains("orders"))
    }

    func testColumnAfterTableDot() {
        let results = suggestions("SELECT users. FROM users", cursor: "SELECT users.".count)
        let cols = results.filter { $0.kind == .column }.map(\.text)
        XCTAssertEqual(Set(cols), Set(["id", "email", "name"]))
    }

    func testColumnAfterTableDotWithPrefix() {
        let results = suggestions("SELECT users.em", cursor: "SELECT users.em".count)
        XCTAssertEqual(results.map(\.text), ["email"])
    }

    func testNoSuggestionsInsideStringLiteral() {
        let text = "SELECT 'hello"
        let results = suggestions(text)
        XCTAssertTrue(results.isEmpty)
    }

    func testNoSuggestionsInsideLineComment() {
        let text = "-- SELECT FR"
        let results = suggestions(text)
        XCTAssertTrue(results.isEmpty)
    }

    func testNoSuggestionsInsideBlockComment() {
        let text = "/* SELECT FR"
        let results = suggestions(text)
        XCTAssertTrue(results.isEmpty)
    }

    func testMysqlBackticksKeywordPresent() {
        let results = suggestions("SHO", dialect: .mysql)
        let texts = results.map(\.text)
        XCTAssertTrue(texts.contains("SHOW"))
    }

    func testEmptyPrefixReturnsKeywords() {
        let results = suggestions("")
        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains { $0.kind == .keyword && $0.text == "SELECT" })
    }

    func testUnknownQualifierReturnsEmptyColumns() {
        let results = suggestions("SELECT foo.b", cursor: "SELECT foo.b".count)
        XCTAssertTrue(results.filter { $0.kind == .column }.isEmpty)
    }

    func testCursorAfterStringLiteralAllowsSuggestions() {
        let text = "SELECT 'x' FR"
        let results = suggestions(text)
        XCTAssertTrue(results.contains { $0.text == "FROM" })
    }

    func testInsertIntoTableSuggestion() {
        let results = suggestions("INSERT INTO us")
        let tableNames = results.filter { $0.kind == .table }.map(\.text)
        XCTAssertTrue(tableNames.contains("users"))
    }
}
