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

        do {
            _ = try await client.query("SELECT 1")
        } catch {
            await close()
            throw Self.translate(error)
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
            throw Self.translate(error)
        }

        var columns: [String] = []
        var rendered: [[String?]] = []
        for try await row in rows {
            if columns.isEmpty {
                columns = row.map(\.columnName)
            }
            rendered.append(row.map(Self.render))
        }

        // PostgresClient's async API does not expose the command tag (rows
        // affected) after iteration. DML without RETURNING leaves rowsAffected nil.
        return QueryResult(columns: columns, rows: rendered)
    }

    public func close() async {
        let task = state.withLock { s -> Task<Void, Never>? in
            let t = s.runTask
            s.client = nil
            s.runTask = nil
            return t
        }
        // Cancel but do NOT `await task.value`: PostgresClient.run() reacts to
        // graceful-shutdown signals (ServiceLifecycle), not Task cancellation, so
        // awaiting the run task here can block indefinitely. Cancellation still
        // tears the pool down asynchronously.
        task?.cancel()
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

    /// Convert a PostgresNIO error into a `DatabaseError` that carries the real
    /// server message and SQLSTATE.
    ///
    /// PostgresNIO's `PSQLError` deliberately overrides `description` to return
    /// a generic placeholder ("Generic description to prevent accidental leakage
    /// of sensitive data") so apps don't accidentally log secrets. We're a GUI
    /// client where the user *is* the secret-owner, so we read the structured
    /// `serverInfo` fields directly and fall back to `String(reflecting:)`
    /// (CustomDebugStringConvertible) only when there's no server response —
    /// e.g. connection-lost or local config errors.
    static func translate(_ error: any Error) -> DatabaseError {
        guard let psql = error as? PSQLError else {
            return .driver(String(reflecting: error))
        }
        if let info = psql.serverInfo, let message = info[.message] {
            let position = info[.position].flatMap(Int.init)
            return .query(code: info[.sqlState], message: message, hint: info[.hint], position: position)
        }
        switch psql.code {
        case .clientClosedConnection, .serverClosedConnection, .uncleanShutdown:
            return .driver("connection closed")
        case .queryCancelled:
            return .driver("query cancelled")
        default:
            return .driver(String(reflecting: error))
        }
    }

    /// Render a cell to a display string.
    ///
    /// Typed decoders are tried first because they are OID-gated and only succeed
    /// for their own column type. `String` is tried LAST: PostgresNIO's `String`
    /// decoder has a permissive `default` case that converts the raw bytes of *any*
    /// type to a string (e.g. for `ltree`), which would render a `float8` as binary
    /// garbage if tried first.
    private static func render(_ cell: PostgresCell) -> String? {
        guard cell.bytes != nil else { return nil }  // SQL NULL
        if let b = try? cell.decode(Bool.self) { return String(b) }
        if let i = try? cell.decode(Int64.self) { return String(i) }
        if let i = try? cell.decode(Int32.self) { return String(i) }
        if let i = try? cell.decode(Int16.self) { return String(i) }
        if let d = try? cell.decode(Double.self) { return String(d) }
        if let f = try? cell.decode(Float.self) { return String(f) }
        if let n = try? cell.decode(Decimal.self) { return n.description }
        if let u = try? cell.decode(UUID.self) { return u.uuidString }
        if let date = try? cell.decode(Date.self) { return date.formatted(.iso8601) }
        if let s = try? cell.decode(String.self) { return s }
        if let buffer = cell.bytes {
            let hex = buffer.readableBytesView.map { String(format: "%02x", $0) }.joined()
            return "\\x" + hex
        }
        return nil
    }
}
