// ResultRowCellOrderingTests.swift
import XCTest
@testable import OpenrowDBCore

final class ResultRowCellOrderingTests: XCTestCase {
  func testNullsLast() {
    XCTAssertEqual(ResultRowCellOrdering.compare(nil, "a"), .orderedDescending)
    XCTAssertEqual(ResultRowCellOrdering.compare("a", nil), .orderedAscending)
    XCTAssertEqual(ResultRowCellOrdering.compare(nil, nil), .orderedSame)
  }

  func testNumeric() {
    XCTAssertEqual(ResultRowCellOrdering.compare("2", "10"), .orderedAscending)
    XCTAssertEqual(ResultRowCellOrdering.compare("10.5", "10.50"), .orderedSame)
  }

  func testText() {
    XCTAssertEqual(ResultRowCellOrdering.compare("alice", "bob"), .orderedAscending)
    XCTAssertEqual(ResultRowCellOrdering.compare("bob", "alice"), .orderedDescending)
  }
}