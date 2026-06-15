// ConnectionTests.swift
import XCTest
@testable import OpenrowDBCore

final class ConnectionTests: XCTestCase {
    func testDefaultPorts() {
        XCTAssertEqual(Connection.Driver.postgres.defaultPort, 5432)
        XCTAssertEqual(Connection.Driver.mysql.defaultPort, 3306)
    }

    func testCodableRoundTrip() throws {
        let original = Connection(
            name: "local-pg",
            driver: .postgres,
            host: "127.0.0.1",
            port: 5432,
            user: "postgres",
            passwordKeychainKey: "openrowdb.test.local-pg",
            database: "postgres",
            sslMode: .prefer
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Connection.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
