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
public final class MySQLDriver: DatabaseClient {
    private let connection: Connection
    private let password: String?
    private let state = Mutex<State>(State())

    private struct State {
        var connection: MySQLConnection?
        var group: EventLoopGroup?
    }

    public let dialect: SQLDialect = .mysql

    public init(connection: Connection, password: String?) {
        self.connection = connection
        self.password = password
    }

    public func connect() async throws {
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
                tlsConfiguration: Self.tls(for: connection.sslMode),
                serverHostname: connection.host,
                on: group.next()
            ).get()
            state.withLock {
                $0.connection = conn
                $0.group = group
            }
        } catch {
            try? await group.shutdownGracefully()
            throw Self.translate(error)
        }
    }

    public func query(_ sql: String) async throws -> QueryResult {
        guard let conn = state.withLock({ $0.connection }) else {
            throw DatabaseError.notConnected
        }

        let rows: [MySQLRow]
        do {
            rows = try await conn.simpleQuery(sql).get()
        } catch {
            throw Self.translate(error)
        }

        guard let first = rows.first else {
            return .empty
        }
        let columns = first.columnDefinitions.map(\.name)
        let rendered = rows.map { row in
            columns.map { name in row.column(name).flatMap(Self.render) }
        }
        return QueryResult(columns: columns, rows: rendered)
    }

    public func close() async {
        let (conn, group) = state.withLock { s -> (MySQLConnection?, EventLoopGroup?) in
            let pair = (s.connection, s.group)
            s.connection = nil
            s.group = nil
            return pair
        }
        // Best-effort close; ignore failure since we are tearing down anyway.
        _ = try? await conn?.close().get()
        try? await group?.shutdownGracefully()
    }

    // MARK: - Helpers

    /// `disable` → plaintext; `prefer`/`require` → TLS without cert verification (post-v1: verify-full).
    private static func tls(for mode: Connection.SSLMode) -> TLSConfiguration? {
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

    private static func render(_ data: MySQLData) -> String? {
        if let s = data.string { return s }
        if let i = data.int { return String(i) }
        if let d = data.double { return String(d) }
        if let b = data.bool { return String(b) }
        return data.description
    }
}
