// PostgresDriver.swift
import Foundation
import NIOSSL
import PostgresNIO
import Synchronization

/// `DatabaseClient` backed by PostgresNIO's pooled `PostgresClient`.
///
/// The client requires its `run()` method to be driven by a long-lived task while
/// connections are leased; we own that task and cancel it on `close()`.
public final class PostgresDriver: DatabaseClient {
    private let connection: Connection
    private let password: String?
    private let state = Mutex<State>(State())

    private struct State {
        var client: PostgresClient?
        var runTask: Task<Void, Never>?
    }

    public let dialect: SQLDialect = .postgres

    public init(connection: Connection, password: String?) {
        self.connection = connection
        self.password = password
    }

    public func connect() async throws {
        let config = PostgresClient.Configuration(
            host: connection.host,
            port: connection.port,
            username: connection.user,
            password: password,
            database: connection.database,
            tls: Self.tls(for: connection.sslMode)
        )
        let client = PostgresClient(configuration: config)
        let runTask = Task { await client.run() }
        state.withLock {
            $0.client = client
            $0.runTask = runTask
        }

        // Round-trip to surface auth/host errors at connect time, not first query.
        do {
            _ = try await client.query("SELECT 1")
        } catch {
            await close()
            throw DatabaseError.driver(String(describing: error))
        }
    }

    public func query(_ sql: String) async throws -> QueryResult {
        guard let client = state.withLock({ $0.client }) else {
            throw DatabaseError.notConnected
        }

        let rows: PostgresRowSequence
        do {
            rows = try await client.query(PostgresQuery(unsafeSQL: sql))
        } catch {
            throw DatabaseError.driver(String(describing: error))
        }

        var columns: [String] = []
        var rendered: [[String?]] = []
        for try await row in rows {
            if columns.isEmpty {
                columns = row.map(\.columnName)
            }
            rendered.append(row.map(Self.render))
        }
        return QueryResult(columns: columns, rows: rendered)
    }

    public func close() async {
        let task = state.withLock { s -> Task<Void, Never>? in
            let t = s.runTask
            s.client = nil
            s.runTask = nil
            return t
        }
        task?.cancel()
        await task?.value
    }

    // MARK: - Helpers

    /// Maps our `SSLMode` to PostgresNIO TLS. `prefer`/`require` both encrypt;
    /// neither verifies the server cert yet (verify-full is a post-v1 enhancement),
    /// matching libpq's default behaviour for these modes against dev servers.
    private static func tls(for mode: Connection.SSLMode) -> PostgresClient.Configuration.TLS {
        switch mode {
        case .disable:
            return .disable
        case .prefer:
            return .prefer(insecureClientConfig())
        case .require:
            return .require(insecureClientConfig())
        }
    }

    private static func insecureClientConfig() -> TLSConfiguration {
        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .none
        return config
    }

    /// Render a cell to a display string, trying common types before falling back to raw bytes.
    private static func render(_ cell: PostgresCell) -> String? {
        guard cell.bytes != nil else { return nil }  // SQL NULL
        if let s = try? cell.decode(String.self) { return s }
        if let i = try? cell.decode(Int64.self) { return String(i) }
        if let d = try? cell.decode(Double.self) { return String(d) }
        if let b = try? cell.decode(Bool.self) { return String(b) }
        if let u = try? cell.decode(UUID.self) { return u.uuidString }
        if let buffer = cell.bytes {
            let hex = buffer.readableBytesView.map { String(format: "%02x", $0) }.joined()
            return "\\x" + hex
        }
        return nil
    }
}
