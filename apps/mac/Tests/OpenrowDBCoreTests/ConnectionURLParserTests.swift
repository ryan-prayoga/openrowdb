// ConnectionURLParserTests.swift
import XCTest
@testable import OpenrowDBCore

final class ConnectionURLParserTests: XCTestCase {
  func testPostgresURL() throws {
    let parsed = try ConnectionURLParser.parse("postgres://alice:secret@db.example.com:5433/mydb")
    XCTAssertEqual(parsed.driver, .postgres)
    XCTAssertEqual(parsed.host, "db.example.com")
    XCTAssertEqual(parsed.port, 5433)
    XCTAssertEqual(parsed.user, "alice")
    XCTAssertEqual(parsed.password, "secret")
    XCTAssertEqual(parsed.database, "mydb")
  }

  func testMySQLURL() throws {
    let parsed = try ConnectionURLParser.parse("mysql://root@127.0.0.1:3306/app")
    XCTAssertEqual(parsed.driver, .mysql)
    XCTAssertEqual(parsed.host, "127.0.0.1")
    XCTAssertEqual(parsed.port, 3306)
    XCTAssertEqual(parsed.user, "root")
    XCTAssertEqual(parsed.database, "app")
  }

  func testInvalidScheme() {
    XCTAssertThrowsError(try ConnectionURLParser.parse("redis://localhost")) { error in
      XCTAssertEqual(error as? ConnectionURLParser.ParseError, .invalidScheme("redis"))
    }
  }
}