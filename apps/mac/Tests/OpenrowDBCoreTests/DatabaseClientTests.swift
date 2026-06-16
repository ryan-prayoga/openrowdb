// DatabaseClientTests.swift
import XCTest
@testable import OpenrowDBCore

/// Returns a fixed result for any query, so default introspection parsing can be
/// tested without a database.
private struct StubClient: DatabaseClient {
    let dialect: SQLDialect
    let result: QueryResult

    func connect() async throws {}
    func query(_ sql: String) async throws -> QueryResult { result }
    func close() async {}
}

final class DatabaseClientTests: XCTestCase {
    func testListTablesParsesKinds() async throws {
        let result = QueryResult(columns: ["table_schema", "table_name", "table_type"], rows: [
            ["public", "Movie", "BASE TABLE"],
            ["public", "active_users", "VIEW"],
        ])
        let client = StubClient(dialect: .postgres, result: result)
        let tables = try await client.listTables()
        XCTAssertEqual(tables.map(\.name), ["Movie", "active_users"])
        XCTAssertEqual(tables.map(\.kind), [.table, .view])
    }

    func testColumnsParsesNameAndType() async throws {
        let result = QueryResult(columns: ["column_name", "data_type"], rows: [
            ["id", "integer"],
            ["title", "text"],
        ])
        let client = StubClient(dialect: .postgres, result: result)
        let columns = try await client.columns(of: TableRef(schema: "public", name: "Movie"))
        XCTAssertEqual(columns, [ColumnInfo(name: "id", type: "integer"), ColumnInfo(name: "title", type: "text")])
    }

    func testEstimatedRowCountParsesFloat() async throws {
        let client = StubClient(dialect: .postgres, result: QueryResult(columns: ["estimate"], rows: [["1234"]]))
        let count = try await client.estimatedRowCount(of: TableRef(schema: "s", name: "t"))
        XCTAssertEqual(count, 1234)
    }

    func testEstimatedRowCountNegativeIsNil() async throws {
        let client = StubClient(dialect: .postgres, result: QueryResult(columns: ["estimate"], rows: [["-1"]]))
        let count = try await client.estimatedRowCount(of: TableRef(schema: "s", name: "t"))
        XCTAssertNil(count)
    }

    // MARK: - Error humanizing

    func testUserMessageMapsRefused() {
        XCTAssertEqual(
            DatabaseError.driver("connectionRefused").userMessage,
            "Connection refused — is the server running and reachable on that host/port?"
        )
    }

    func testUserMessageMapsAuth() {
        XCTAssertTrue(DatabaseError.driver("authentication failed for user").userMessage.contains("Authentication failed"))
    }

    func testUserMessageInvalidAddress() {
        XCTAssertTrue(DatabaseError.invalidAddress("bad host").userMessage.contains("bad host"))
    }

    func testIsConnectionLost() {
        XCTAssertTrue(DatabaseError.notConnected.isConnectionLost)
        XCTAssertTrue(DatabaseError.driver("the connection is closed").isConnectionLost)
        XCTAssertTrue(DatabaseError.driver("server closed the connection").isConnectionLost)
        XCTAssertFalse(DatabaseError.driver("syntax error at or near \"slect\"").isConnectionLost)
        XCTAssertFalse(DatabaseError.invalidAddress("x").isConnectionLost)
        XCTAssertFalse(DatabaseError.query(code: "42P01", message: "relation does not exist", hint: nil).isConnectionLost)
    }

    func testQueryErrorUserMessageWithCodeAndHint() {
        let err = DatabaseError.query(
            code: "42P01",
            message: "relation \"usrs\" does not exist",
            hint: "Perhaps you meant \"users\"."
        )
        let msg = err.userMessage
        XCTAssertTrue(msg.contains("relation \"usrs\" does not exist"))
        XCTAssertTrue(msg.contains("42P01"))
        XCTAssertTrue(msg.contains("Hint: Perhaps you meant \"users\"."))
    }

    func testQueryErrorUserMessageWithoutCode() {
        let err = DatabaseError.query(code: nil, message: "Table 'db.foo' doesn't exist", hint: nil)
        XCTAssertEqual(err.userMessage, "Table 'db.foo' doesn't exist")
    }

    func testQueryErrorEquatable() {
        let a = DatabaseError.query(code: "42P01", message: "x", hint: nil)
        let b = DatabaseError.query(code: "42P01", message: "x", hint: nil)
        let c = DatabaseError.query(code: "42P02", message: "x", hint: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
