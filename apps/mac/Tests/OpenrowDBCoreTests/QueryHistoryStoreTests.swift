// QueryHistoryStoreTests.swift
import XCTest
@testable import OpenrowDBCore

final class QueryHistoryStoreTests: XCTestCase {
    private var tempDir: URL!
    private var dbURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OpenrowDBHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbURL = tempDir.appendingPathComponent("history.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    private func makeStore() throws -> QueryHistoryStore {
        try QueryHistoryStore(fileURL: dbURL)
    }

    private func makeEntry(
        connection: UUID,
        sql: String = "SELECT 1",
        executedAt: Date = Date(),
        durationMs: Int = 12,
        rowsAffected: Int? = nil,
        error: String? = nil
    ) -> HistoryEntry {
        HistoryEntry(
            connectionID: connection,
            sql: sql,
            executedAt: executedAt,
            durationMs: durationMs,
            rowsAffected: rowsAffected,
            error: error
        )
    }

    func testInsertAndFetchRoundtrip() async throws {
        let store = try makeStore()
        let conn = UUID()
        let entry = makeEntry(connection: conn, sql: "SELECT 42", durationMs: 7, rowsAffected: 1)

        try await store.record(entry)

        let fetched = try await store.entries(forConnection: conn)
        XCTAssertEqual(fetched.count, 1)
        let got = fetched[0]
        XCTAssertEqual(got.id, entry.id)
        XCTAssertEqual(got.connectionID, entry.connectionID)
        XCTAssertEqual(got.sql, entry.sql)
        XCTAssertEqual(got.durationMs, entry.durationMs)
        XCTAssertEqual(got.rowsAffected, entry.rowsAffected)
        XCTAssertNil(got.error)
        // GRDB serializes Date to SQLite TEXT with millisecond precision, so the
        // round-trip can drift by a sub-ms fraction from the original `Date()`.
        XCTAssertEqual(got.executedAt.timeIntervalSince1970, entry.executedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testEntriesAreNewestFirst() async throws {
        let store = try makeStore()
        let conn = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let oldest = makeEntry(connection: conn, sql: "SELECT 1", executedAt: base)
        let middle = makeEntry(connection: conn, sql: "SELECT 2", executedAt: base.addingTimeInterval(10))
        let newest = makeEntry(connection: conn, sql: "SELECT 3", executedAt: base.addingTimeInterval(20))

        try await store.record(oldest)
        try await store.record(middle)
        try await store.record(newest)

        let fetched = try await store.entries(forConnection: conn)
        XCTAssertEqual(fetched.map(\.sql), ["SELECT 3", "SELECT 2", "SELECT 1"])
    }

    func testFilterByConnection() async throws {
        let store = try makeStore()
        let connA = UUID()
        let connB = UUID()

        try await store.record(makeEntry(connection: connA, sql: "A-1"))
        try await store.record(makeEntry(connection: connA, sql: "A-2"))
        try await store.record(makeEntry(connection: connB, sql: "B-1"))

        let a = try await store.entries(forConnection: connA)
        let b = try await store.entries(forConnection: connB)

        XCTAssertEqual(Set(a.map(\.sql)), ["A-1", "A-2"])
        XCTAssertEqual(b.map(\.sql), ["B-1"])
    }

    func testLimitIsRespected() async throws {
        let store = try makeStore()
        let conn = UUID()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for i in 0..<5 {
            try await store.record(makeEntry(
                connection: conn,
                sql: "SELECT \(i)",
                executedAt: base.addingTimeInterval(Double(i))
            ))
        }

        let limited = try await store.entries(forConnection: conn, limit: 2)
        XCTAssertEqual(limited.count, 2)
        XCTAssertEqual(limited.map(\.sql), ["SELECT 4", "SELECT 3"])
    }

    func testAllEntriesAcrossConnections() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        try await store.record(makeEntry(connection: UUID(), sql: "A", executedAt: base))
        try await store.record(makeEntry(connection: UUID(), sql: "B", executedAt: base.addingTimeInterval(1)))
        try await store.record(makeEntry(connection: UUID(), sql: "C", executedAt: base.addingTimeInterval(2)))

        let all = try await store.allEntries()
        XCTAssertEqual(all.map(\.sql), ["C", "B", "A"])
    }

    func testDeleteSingleEntry() async throws {
        let store = try makeStore()
        let conn = UUID()
        let keep = makeEntry(connection: conn, sql: "KEEP")
        let drop = makeEntry(connection: conn, sql: "DROP")

        try await store.record(keep)
        try await store.record(drop)
        try await store.delete(id: drop.id)

        let remaining = try await store.entries(forConnection: conn)
        XCTAssertEqual(remaining.map(\.sql), ["KEEP"])
    }

    func testClearByConnection() async throws {
        let store = try makeStore()
        let connA = UUID()
        let connB = UUID()

        try await store.record(makeEntry(connection: connA, sql: "A-1"))
        try await store.record(makeEntry(connection: connA, sql: "A-2"))
        try await store.record(makeEntry(connection: connB, sql: "B-1"))

        try await store.clear(connectionID: connA)

        let aRemaining = try await store.entries(forConnection: connA)
        let bRemaining = try await store.entries(forConnection: connB)
        XCTAssertTrue(aRemaining.isEmpty)
        XCTAssertEqual(bRemaining.map(\.sql), ["B-1"])
    }

    func testClearAll() async throws {
        let store = try makeStore()
        let conn = UUID()
        try await store.record(makeEntry(connection: conn, sql: "X"))
        try await store.record(makeEntry(connection: UUID(), sql: "Y"))

        try await store.clearAll()

        let remaining = try await store.allEntries()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testFailedQueryPersistsError() async throws {
        let store = try makeStore()
        let conn = UUID()
        let entry = makeEntry(
            connection: conn,
            sql: "SELECT * FROM no_such_table",
            durationMs: 3,
            error: "relation \"no_such_table\" does not exist"
        )

        try await store.record(entry)

        let fetched = try await store.entries(forConnection: conn)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertNil(fetched[0].rowsAffected)
        XCTAssertEqual(fetched[0].error, "relation \"no_such_table\" does not exist")
    }

    func testMigrationIsIdempotent() async throws {
        let store1 = try makeStore()
        let conn = UUID()
        try await store1.record(makeEntry(connection: conn, sql: "PERSISTED"))

        // Re-open the same file; migrator should no-op and preserve data.
        let store2 = try makeStore()
        let entries = try await store2.entries(forConnection: conn)
        XCTAssertEqual(entries.map(\.sql), ["PERSISTED"])
    }
}
