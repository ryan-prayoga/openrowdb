// PostgresDriverLifecycleTests.swift
import XCTest
@testable import OpenrowDBCore

final class PostgresDriverLifecycleTests: XCTestCase {
    private func liveConnection(database: String = "openrow_demo_shop") -> Connection {
        Connection(
            name: "PG lifecycle",
            driver: .postgres,
            host: "127.0.0.1",
            port: 5432,
            user: "ryanprayoga",
            passwordKeychainKey: "pg-lifecycle",
            database: database,
            sslMode: .disable
        )
    }

    func testRapidConnectDisconnectCycles() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENROW_LIVE_DB"] == "1")

        let driver = PostgresDriver(connection: liveConnection(), password: "")
        for _ in 0 ..< 10 {
            try await driver.connect()
            _ = try await driver.query("SELECT 1")
            await driver.close()
        }
    }

    func testConcurrentQueriesSerializeWithoutHanging() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENROW_LIVE_DB"] == "1")

        let driver = PostgresDriver(connection: liveConnection(), password: "")
        try await driver.connect()
        defer { Task { await driver.close() } }

        try await withThrowingTaskGroup(of: QueryResult.self) { group in
            for index in 0 ..< 20 {
                group.addTask {
                    try await driver.query("SELECT \(index) AS n")
                }
            }
            var count = 0
            for try await _ in group {
                count += 1
            }
            XCTAssertEqual(count, 20)
        }
        await driver.close()
    }

    func testFailedConnectThenCloseDoesNotTrap() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENROW_LIVE_DB"] == "1")

        var bad = liveConnection()
        bad.port = 59_999
        let driver = PostgresDriver(connection: bad, password: "")
        do {
            try await driver.connect()
            XCTFail("expected connect to fail")
        } catch {
            // expected
        }
        await driver.close()
    }
}