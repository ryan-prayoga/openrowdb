// ConnectionManagerTests.swift
import XCTest
import Synchronization
@testable import OpenrowDBCore

/// Records calls and returns canned data so manager orchestration can be tested
/// without a live database.
private final class MockDatabaseClient: DatabaseClient {
    struct State {
        var connectCalls = 0
        var closeCalls = 0
        var lastSQL: String?
    }

    let state = Mutex<State>(State())
    let shouldFailConnect: Bool
    let cannedResult: QueryResult
    let dialect: SQLDialect = .postgres

    init(shouldFailConnect: Bool = false, cannedResult: QueryResult = .empty) {
        self.shouldFailConnect = shouldFailConnect
        self.cannedResult = cannedResult
    }

    func connect() async throws {
        state.withLock { $0.connectCalls += 1 }
        if shouldFailConnect { throw DatabaseError.driver("boom") }
    }

    func query(_ sql: String) async throws -> QueryResult {
        state.withLock { $0.lastSQL = sql }
        return cannedResult
    }

    func close() async {
        state.withLock { $0.closeCalls += 1 }
    }
}

@MainActor
final class ConnectionManagerTests: XCTestCase {
    nonisolated(unsafe) private var tempDir: URL!

    private func makeManager(
        client: MockDatabaseClient = MockDatabaseClient(),
        onPassword: (@Sendable (String?) -> Void)? = nil
    ) throws -> ConnectionManager {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("orm-\(UUID().uuidString)", isDirectory: true)
        let store = try ConnectionStore(fileURL: tempDir.appendingPathComponent("c.json"))
        let secrets = InMemorySecretStore()
        return ConnectionManager(store: store, secrets: secrets) { _, password in
            onPassword?(password)
            return client
        }
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func sampleConnection() -> Connection {
        Connection(
            name: "local",
            driver: .postgres,
            host: "127.0.0.1",
            port: 5432,
            user: "postgres",
            passwordKeychainKey: "openrowdb.local",
            database: "postgres"
        )
    }

    func testAddPersistsAndSetsDisconnected() throws {
        let manager = try makeManager()
        let conn = sampleConnection()
        try manager.add(conn, password: "pw")

        XCTAssertEqual(manager.connections.map { $0.id }, [conn.id])
        XCTAssertEqual(manager.status[conn.id], ConnectionManager.Status.disconnected)
    }

    func testConnectSuccessSetsConnectedAndResolvesPassword() async throws {
        let client = MockDatabaseClient()
        let sink = Mutex<String?>(nil)
        let manager = try makeManager(client: client) { password in
            sink.withLock { $0 = password }
        }
        let conn = sampleConnection()
        try manager.add(conn, password: "s3cret")

        await manager.connect(conn.id)

        XCTAssertEqual(manager.status[conn.id], ConnectionManager.Status.connected)
        XCTAssertEqual(client.state.withLock { $0.connectCalls }, 1)
        XCTAssertEqual(sink.withLock { $0 }, "s3cret")
    }

    func testConnectFailureSetsFailedAndClosesClient() async throws {
        let client = MockDatabaseClient(shouldFailConnect: true)
        let manager = try makeManager(client: client)
        let conn = sampleConnection()
        try manager.add(conn, password: "pw")

        await manager.connect(conn.id)

        XCTAssertEqual(manager.status[conn.id], ConnectionManager.Status.failed("boom"))
        XCTAssertEqual(client.state.withLock { $0.closeCalls }, 1)
    }

    func testRunBeforeConnectThrows() async throws {
        let manager = try makeManager()
        let conn = sampleConnection()
        try manager.add(conn, password: "pw")

        do {
            _ = try await manager.run("SELECT 1", on: conn.id)
            XCTFail("expected notConnected")
        } catch let error as DatabaseError {
            XCTAssertEqual(error, .notConnected)
        }
    }

    func testRunAfterConnectReturnsResult() async throws {
        let result = QueryResult(columns: ["n"], rows: [["1"]])
        let client = MockDatabaseClient(cannedResult: result)
        let manager = try makeManager(client: client)
        let conn = sampleConnection()
        try manager.add(conn, password: "pw")
        await manager.connect(conn.id)

        let got = try await manager.run("SELECT 1 AS n", on: conn.id)
        XCTAssertEqual(got, result)
        XCTAssertEqual(client.state.withLock { $0.lastSQL }, "SELECT 1 AS n")
    }

    func testDisconnectClosesAndResets() async throws {
        let client = MockDatabaseClient()
        let manager = try makeManager(client: client)
        let conn = sampleConnection()
        try manager.add(conn, password: "pw")
        await manager.connect(conn.id)

        await manager.disconnect(conn.id)

        XCTAssertEqual(manager.status[conn.id], ConnectionManager.Status.disconnected)
        XCTAssertEqual(client.state.withLock { $0.closeCalls }, 1)
    }

    func testRemoveDeletesEverything() async throws {
        let manager = try makeManager()
        let conn = sampleConnection()
        try manager.add(conn, password: "pw")

        try await manager.remove(conn)

        XCTAssertTrue(manager.connections.isEmpty)
        XCTAssertNil(manager.status[conn.id])
    }

    func testReloadPopulatesStatus() async throws {
        let manager = try makeManager()
        let conn = sampleConnection()
        try manager.add(conn, password: "pw")

        try manager.reload()

        XCTAssertEqual(manager.connections.map { $0.id }, [conn.id])
        XCTAssertEqual(manager.status[conn.id], ConnectionManager.Status.disconnected)
    }
}
