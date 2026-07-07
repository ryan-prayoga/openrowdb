// PostgresCommandTagTests.swift
import XCTest
@testable import OpenrowDBCore

final class PostgresCommandTagTests: XCTestCase {
  func testUpdate() {
    XCTAssertEqual(PostgresCommandTag.rowsAffected(in: "UPDATE 5"), 5)
  }

  func testDelete() {
    XCTAssertEqual(PostgresCommandTag.rowsAffected(in: "DELETE 0"), 0)
  }

  func testInsert() {
    XCTAssertEqual(PostgresCommandTag.rowsAffected(in: "INSERT 0 1"), 1)
  }

  func testSelectWithCount() {
    XCTAssertEqual(PostgresCommandTag.rowsAffected(in: "SELECT 42"), 42)
  }

  func testSelectWithoutCount() {
    XCTAssertNil(PostgresCommandTag.rowsAffected(in: "SELECT"))
  }

  func testCreateTable() {
    XCTAssertNil(PostgresCommandTag.rowsAffected(in: "CREATE TABLE"))
  }
}