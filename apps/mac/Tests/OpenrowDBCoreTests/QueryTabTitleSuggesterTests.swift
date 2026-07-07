// QueryTabTitleSuggesterTests.swift
import XCTest
@testable import OpenrowDBCore

final class QueryTabTitleSuggesterTests: XCTestCase {
  func testFromClause() {
    let title = QueryTabTitleSuggester.suggest(from: "SELECT * FROM users WHERE id = 1")
    XCTAssertEqual(title, "users")
  }

  func testQuotedTable() {
    let title = QueryTabTitleSuggester.suggest(from: "select count(*) from \"Movie\"")
    XCTAssertEqual(title, "Movie")
  }

  func testNoFromReturnsNil() {
    XCTAssertNil(QueryTabTitleSuggester.suggest(from: "SELECT 1"))
  }
}