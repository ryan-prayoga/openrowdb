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

    func testCodableBackwardCompatibility() throws {
        let legacyJSON = """
        {
          "database": "postgres",
          "driver": "postgres",
          "host": "127.0.0.1",
          "id": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
          "name": "legacy",
          "passwordKeychainKey": "key",
          "port": 5432,
          "sslMode": "prefer",
          "user": "postgres"
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Connection.self, from: legacyJSON)
        XCTAssertFalse(decoded.ssh.enabled)
        XCTAssertFalse(decoded.isReadOnly)
    }

    func testCodableWithSSHAndReadOnly() throws {
        var original = Connection(
            name: "bastion",
            driver: .mysql,
            host: "10.0.0.5",
            port: 3306,
            user: "root",
            passwordKeychainKey: "key",
            database: "app",
            isReadOnly: true
        )
        original.ssh = SSHTunnelConfig(enabled: true, host: "jump.example.com", port: 22, user: "ubuntu")

        let decoded = try JSONDecoder().decode(Connection.self, from: JSONEncoder().encode(original))
        XCTAssertTrue(decoded.isReadOnly)
        XCTAssertEqual(decoded.ssh.host, "jump.example.com")
    }
}
