// ColumnEditKindTests.swift
import XCTest
@testable import OpenrowDBCore

final class ColumnEditKindTests: XCTestCase {
  func testJson() {
    XCTAssertEqual(ColumnEditKindResolver.kind(for: "jsonb"), .json)
  }

  func testBoolean() {
    XCTAssertEqual(ColumnEditKindResolver.kind(for: "boolean"), .boolean)
    XCTAssertEqual(ColumnEditKindResolver.kind(for: "tinyint(1)"), .boolean)
  }

  func testDate() {
    XCTAssertEqual(ColumnEditKindResolver.kind(for: "date"), .date)
  }

  func testDateTime() {
    XCTAssertEqual(ColumnEditKindResolver.kind(for: "timestamptz"), .dateTime)
    XCTAssertEqual(ColumnEditKindResolver.kind(for: "datetime"), .dateTime)
  }

  func testTextFallback() {
    XCTAssertEqual(ColumnEditKindResolver.kind(for: "varchar(255)"), .text)
  }
}