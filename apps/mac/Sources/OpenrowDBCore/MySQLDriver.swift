// MySQLDriver.swift
import Foundation
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL
import Synchronization

/// `DatabaseClient` backed by MySQLNIO.
///
/// MySQLNIO is `EventLoopFuture`-based; we bridge to async via `.get()` and own a
/// single-thread `EventLoopGroup` that is shut down on `close()`.
///
/// All operations run through a private `Session` actor so concurrent callers never
/// issue overlapping queries on the same wire connection.
public final class MySQLDriver: DatabaseClient, @unchecked Sendable {
    private let session: Session

    public let dialect: SQLDialect = .mysql

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

    /// `disable` → plaintext; `prefer`/`require` → TLS without cert verification (post-v1: verify-full).
    fileprivate static func tls(for mode: Connection.SSLMode) -> TLSConfiguration? {
        switch mode {
        case .disable:
            return nil
        case .prefer, .require:
            var config = TLSConfiguration.makeClientConfiguration()
            config.certificateVerification = .none
            return config
        }
    }

    /// Convert a MySQLNIO error into a `DatabaseError` carrying the structured
    /// server response (errno + SQLSTATE + message) instead of MySQLNIO's
    /// `CustomStringConvertible` wrapper, which prefixes "MySQL error:" and
    /// hides the fields the UI wants to format.
    static func translate(_ error: any Error) -> DatabaseError {
        guard let my = error as? MySQLError else {
            return .driver(String(reflecting: error))
        }
        switch my {
        case .server(let packet):
            let code = packet.sqlState ?? String(packet.errorCode.rawValue)
            return .query(code: code, message: packet.errorMessage, hint: nil, position: nil)
        case .duplicateEntry(let message), .invalidSyntax(let message):
            return .query(code: nil, message: message, hint: nil, position: nil)
        case .closed:
            return .driver("connection closed")
        default:
            return .driver(my.message)
        }
    }

    fileprivate static func render(_ data: MySQLData) -> String? {
        if let s = data.string { return s }
        if let i = data.int { return String(i) }
        if let d = data.double { return String(d) }
        if let b = data.bool { return String(b) }
        return data.description
    }
}

// MARK: - Session

private actor Session {
    private let connection: Connection
    private let password: String?
    private var mysqlConnection: MySQLConnection?
    private var group: EventLoopGroup?

    init(connection: Connection, password: String?) {
        self.connection = connection
        self.password = password
    }

    func connect() async throws {
        if mysqlConnection != nil { return }

        let address: SocketAddress
        do {
            address = try SocketAddress.makeAddressResolvingHost(connection.host, port: connection.port)
        } catch {
            throw DatabaseError.invalidAddress(connection.host)
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        do {
            let conn = try await MySQLConnection.connect(
                to: address,
                username: connection.user,
                database: connection.database,
                password: password,
                tlsConfiguration: MySQLDriver.tls(for: connection.sslMode),
                serverHostname: connection.host,
                on: group.next()
            ).get()
            mysqlConnection = conn
            self.group = group
        } catch {
            try? await group.shutdownGracefully()
            throw MySQLDriver.translate(error)
        }
    }

    func query(_ sql: String) async throws -> QueryResult {
        guard let conn = mysqlConnection else {
            throw DatabaseError.notConnected
        }

        let box = Mutex<(rows: [MySQLRow], metadata: MySQLQueryMetadata?)>((rows: [], metadata: nil))
        do {
            try await conn.query(
                sql,
                onRow: { row in
                    box.withLock { $0.rows.append(row) }
                },
                onMetadata: { metadata in
                    box.withLock { $0.metadata = metadata }
                }
            ).get()
        } catch {
            throw MySQLDriver.translate(error)
        }

        var capturedRows: [MySQLRow] = []
        var rowsAffected: Int?
        box.withLock {
            capturedRows = $0.rows
            rowsAffected = $0.metadata.map { Int($0.affectedRows) }
        }

        guard let first = capturedRows.first else {
            return QueryResult(columns: [], rows: [], rowsAffected: rowsAffected)
        }
        let columns = first.columnDefinitions.map(\.name)
        let rendered = capturedRows.map { row in
            columns.map { name in row.column(name).flatMap(MySQLDriver.render) }
        }
        return QueryResult(columns: columns, rows: rendered, rowsAffected: rowsAffected)
    }

    func close() async {
        let conn = mysqlConnection
        let group = self.group
        mysqlConnection = nil
        self.group = nil
        _ = try? await conn?.close().get()
        try? await group?.shutdownGracefully()
    }
}