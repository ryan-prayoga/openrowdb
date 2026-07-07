// TabularPasteParserTests.swift
import XCTest
@testable import OpenrowDBCore

final class TabularPasteParserTests: XCTestCase {
  private let columns = ["id", "name", "email"]

  func testTSVWithHeader() {
    let text = "id\tname\temail\n1\tAlice\talice@example.com\n2\tBob\t\n"
    let result = TabularPasteParser.parse(text, tableColumns: columns)
    XCTAssertEqual(result.rows.count, 2)
    XCTAssertEqual(result.mappedColumns, columns)
    XCTAssertEqual(value(in: result.rows[0], column: "name"), .text("Alice"))
    XCTAssertEqual(value(in: result.rows[1], column: "email"), .null)
  }

  func testCSVQuotedComma() {
    let text = "id,name,email\n1,\"Doe, Jane\",jane@example.com"
    let result = TabularPasteParser.parse(text, tableColumns: columns)
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(value(in: result.rows[0], column: "name"), .text("Doe, Jane"))
  }

  func testPositionalWithoutHeader() {
    let text = "9\tZed\tzed@example.com"
    let result = TabularPasteParser.parse(text, tableColumns: columns)
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(value(in: result.rows[0], column: "id"), .text("9"))
    XCTAssertEqual(value(in: result.rows[0], column: "name"), .text("Zed"))
  }

  func testNullLiterals() {
    let text = "id\tname\temail\n1\tNULL\t\\N"
    let result = TabularPasteParser.parse(text, tableColumns: columns)
    XCTAssertEqual(value(in: result.rows[0], column: "name"), .null)
    XCTAssertEqual(value(in: result.rows[0], column: "email"), .null)
  }

  func testUnmappedHeadersReported() {
    let text = "id\textra\tname\n1\tfoo\tBar"
    let result = TabularPasteParser.parse(text, tableColumns: columns)
    XCTAssertEqual(result.unmappedHeaders, ["extra"])
    XCTAssertEqual(value(in: result.rows[0], column: "name"), .text("Bar"))
  }

  func testTrailingEmptyField() {
    let text = "2\tBob\t\n"
    let result = TabularPasteParser.parse(text, tableColumns: columns)
    XCTAssertEqual(result.rows.count, 1)
    XCTAssertEqual(result.rows[0].assignments.count, 3)
    XCTAssertEqual(value(in: result.rows[0], column: "email"), .null)
  }

  func testEmptyClipboardWarning() {
    let result = TabularPasteParser.parse("   ", tableColumns: columns)
    XCTAssertTrue(result.rows.isEmpty)
    XCTAssertFalse(result.warnings.isEmpty)
  }

  private func value(in row: TabularPasteRow, column: String) -> SQLValue? {
    row.assignments.first(where: { $0.column == column })?.value
  }
}