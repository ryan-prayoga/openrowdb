// SQLWriteDetectorTests.swift
import XCTest
@testable import OpenrowDBCore

final class SQLWriteDetectorTests: XCTestCase {
    func testDetectsInsert() {
        XCTAssertTrue(SQLWriteDetector.isWriteStatement("INSERT INTO users (id) VALUES (1)"))
    }

    func testDetectsUpdate() {
        XCTAssertTrue(SQLWriteDetector.containsWrite("SELECT 1; UPDATE users SET name = 'a' WHERE id = 1"))
    }

    func testExplainIsNotWrite() {
        XCTAssertFalse(SQLWriteDetector.isWriteStatement("EXPLAIN SELECT * FROM users"))
    }

    func testShowIsNotWrite() {
        XCTAssertFalse(SQLWriteDetector.isWriteStatement("SHOW TABLES"))
    }

    func testSelectIsNotWrite() {
        XCTAssertFalse(SQLWriteDetector.containsWrite("SELECT * FROM users WHERE id = 1"))
    }

    func testCreateIsWrite() {
        XCTAssertTrue(SQLWriteDetector.isWriteStatement("CREATE TABLE foo (id int)"))
    }
}