// PostgresDriver.swift
import Foundation
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import PostgresNIO

/// `DatabaseClient` backed by a single `PostgresConnection` (no connection pool).
///
/// PostgresNIO's pooled `PostgresClient` spins up `ConnectionPool` timer tasks that
/// crash under Swift 6 on macOS 26 when connect/test/disconnect races occur. A GUI
/// client only needs one live connection per database, so we mirror `MySQLDriver`:
/// one NIO event loop, one connection, explicit close.
///
/// All operations run through a private `Session` actor so concurrent callers
/// (table browse + sidebar counts + pagination) never issue overlapping queries on
/// the same wire connection, which would otherwise hang indefinitely.
public final class PostgresDriver: DatabaseClient, @unchecked Sendable {
    private let session: Session

    public let dialect: SQLDialect = .postgres

    public init(connection: Connection, password: String?) {
        self.session = Session(connection: connection, password: password)
    }

    public func connect() async throws {
        try await session.connect()
    }

    public func query(_ sql: String) async throws -> QueryResult {
        try await session.query(sql)
    }

    public func close() async {
        await session.close()
    }

    // MARK: - Helpers

    fileprivate static let logger = Logger(label: "com.openrowdb.postgres")

    fileprivate static func tls(for mode: Connection.SSLMode) -> PostgresConnection.Configuration.TLS {
        switch mode {
        case .disable:
            return .disable
        case .prefer, .require:
            guard let context = try? NIOSSLContext(configuration: insecureClientConfig()) else {
                return .disable
            }
            return mode == .prefer ? .prefer(context) : .require(context)
        }
    }

    fileprivate static func insecureClientConfig() -> TLSConfiguration {
        var config = TLSConfiguration.makeClientConfiguration()
        config.certificateVerification = .none
        return config
    }

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

    fileprivate static func render(_ cell: PostgresCell) -> String? {
        guard cell.bytes != nil else { return nil }
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

// MARK: - Session

private actor Session {
    private let connection: Connection
    private let password: String?
    private var postgresConnection: PostgresConnection?
    private var group: EventLoopGroup?

    init(connection: Connection, password: String?) {
        self.connection = connection
        self.password = password
    }

    func connect() async throws {
        if postgresConnection != nil { return }

        let database = connection.database.isEmpty ? nil : connection.database
        let config = PostgresConnection.Configuration(
            host: connection.host,
            port: connection.port,
            username: connection.user,
            password: password,
            database: database,
            tls: PostgresDriver.tls(for: connection.sslMode)
        )

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let conn = try await PostgresConnection.connect(
                on: group.next(),
                configuration: config,
                id: 1,
                logger: PostgresDriver.logger
            )
            _ = try await conn.query(PostgresQuery(unsafeSQL: "SELECT 1"), logger: PostgresDriver.logger)
            postgresConnection = conn
            self.group = group
        } catch {
            try? await group.shutdownGracefully()
            throw PostgresDriver.translate(error)
        }
    }

    func query(_ sql: String) async throws -> QueryResult {
        guard let conn = postgresConnection else {
            throw DatabaseError.notConnected
        }

        let rows: PostgresRowSequence
        do {
            rows = try await conn.query(PostgresQuery(unsafeSQL: sql), logger: PostgresDriver.logger)
        } catch {
            throw PostgresDriver.translate(error)
        }

        var columns: [String] = []
        var rendered: [[String?]] = []
        for try await row in rows {
            if columns.isEmpty {
                columns = row.map(\.columnName)
            }
            rendered.append(row.map(PostgresDriver.render))
        }

        return QueryResult(columns: columns, rows: rendered)
    }

    func close() async {
        let conn = postgresConnection
        let group = self.group
        postgresConnection = nil
        self.group = nil
        try? await conn?.close()
        try? await group?.shutdownGracefully()
    }
}