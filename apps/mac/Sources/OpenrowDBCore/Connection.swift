// Connection.swift
import Foundation

/// Connection descriptor — what the user fills into the new-connection sheet.
public struct Connection: Identifiable, Hashable, Sendable, Codable {
    public enum Driver: String, Codable, Sendable, CaseIterable {
        case postgres
        case mysql
    }

    public enum SSLMode: String, Codable, Sendable, CaseIterable {
        case disable
        case prefer
        case require
    }

    public let id: UUID
    public var name: String
    public var driver: Driver
    public var host: String
    public var port: Int
    public var user: String
    /// Password lives in Keychain; this struct only holds a reference key.
    public var passwordKeychainKey: String
    public var database: String
    public var sslMode: SSLMode

    public init(
        id: UUID = UUID(),
        name: String,
        driver: Driver,
        host: String,
        port: Int,
        user: String,
        passwordKeychainKey: String,
        database: String,
        sslMode: SSLMode = .prefer
    ) {
        self.id = id
        self.name = name
        self.driver = driver
        self.host = host
        self.port = port
        self.user = user
        self.passwordKeychainKey = passwordKeychainKey
        self.database = database
        self.sslMode = sslMode
    }
}

public extension Connection.Driver {
    var defaultPort: Int {
        switch self {
        case .postgres: 5432
        case .mysql: 3306
        }
    }
}
