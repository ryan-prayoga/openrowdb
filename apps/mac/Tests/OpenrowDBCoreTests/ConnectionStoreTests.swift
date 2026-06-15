// ConnectionStoreTests.swift
import XCTest
@testable import OpenrowDBCore

final class ConnectionStoreTests: XCTestCase {
    private var tempDir: URL!
    private var store: ConnectionStore!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openrowdb-tests-\(UUID().uuidString)", isDirectory: true)
        store = try ConnectionStore(fileURL: tempDir.appendingPathComponent("connections.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeConnection(name: String) -> Connection {
        Connection(
            name: name,
            driver: .postgres,
            host: "127.0.0.1",
            port: 5432,
            user: "postgres",
            passwordKeychainKey: "openrowdb.\(name)",
            database: "postgres"
        )
    }

    func testLoadEmptyWhenNoFile() throws {
        XCTAssertEqual(try store.load(), [])
    }

    func testSaveThenLoadRoundTrips() throws {
        let connections = [makeConnection(name: "a"), makeConnection(name: "b")]
        try store.save(connections)
        XCTAssertEqual(try store.load(), connections)
    }

    func testUpsertInsertsAndUpdates() throws {
        var conn = makeConnection(name: "local")
        try store.upsert(conn)
        XCTAssertEqual(try store.load().count, 1)

        conn.host = "db.internal"
        try store.upsert(conn)
        let loaded = try store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.host, "db.internal")
    }

    func testRemoveDeletesById() throws {
        let conn = makeConnection(name: "gone")
        try store.upsert(conn)
        try store.remove(id: conn.id)
        XCTAssertEqual(try store.load(), [])
    }

    func testRemoveMissingIsNoOp() throws {
        try store.remove(id: UUID())
        XCTAssertEqual(try store.load(), [])
    }
}
