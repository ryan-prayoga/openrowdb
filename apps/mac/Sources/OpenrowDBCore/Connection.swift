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
    /// Optional SSH bastion in front of the database host.
    public var ssh: SSHTunnelConfig
    /// When true, mutations and write SQL are blocked client-side.
    public var isReadOnly: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        driver: Driver,
        host: String,
        port: Int,
        user: String,
        passwordKeychainKey: String,
        database: String,
        sslMode: SSLMode = .prefer,
        ssh: SSHTunnelConfig = .disabled,
        isReadOnly: Bool = false
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
        self.ssh = ssh
        self.isReadOnly = isReadOnly
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, driver, host, port, user, passwordKeychainKey, database, sslMode, ssh, isReadOnly
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        driver = try container.decode(Driver.self, forKey: .driver)
        host = try container.decode(String.self, forKey: .host)
        port = try container.decode(Int.self, forKey: .port)
        user = try container.decode(String.self, forKey: .user)
        passwordKeychainKey = try container.decode(String.self, forKey: .passwordKeychainKey)
        database = try container.decode(String.self, forKey: .database)
        sslMode = try container.decodeIfPresent(SSLMode.self, forKey: .sslMode) ?? .prefer
        ssh = try container.decodeIfPresent(SSHTunnelConfig.self, forKey: .ssh) ?? .disabled
        isReadOnly = try container.decodeIfPresent(Bool.self, forKey: .isReadOnly) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(driver, forKey: .driver)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(user, forKey: .user)
        try container.encode(passwordKeychainKey, forKey: .passwordKeychainKey)
        try container.encode(database, forKey: .database)
        try container.encode(sslMode, forKey: .sslMode)
        if ssh.enabled { try container.encode(ssh, forKey: .ssh) }
        if isReadOnly { try container.encode(isReadOnly, forKey: .isReadOnly) }
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
