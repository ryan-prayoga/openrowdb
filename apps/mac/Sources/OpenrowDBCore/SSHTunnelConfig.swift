// SSHTunnelConfig.swift
import Foundation

/// Optional SSH bastion in front of the database host. When enabled, OpenrowDB
/// opens a local port forward before the driver connects.
public struct SSHTunnelConfig: Sendable, Equatable, Hashable, Codable {
    public var enabled: Bool
    public var host: String
    public var port: Int
    public var user: String
    /// Path to a private key (`~` expands). Empty = use the user's default keys.
    public var privateKeyPath: String
    /// Keychain key for the SSH password (login or key passphrase). Nil = none.
    public var passwordKeychainKey: String?

    public init(
        enabled: Bool = false,
        host: String = "",
        port: Int = 22,
        user: String = "",
        privateKeyPath: String = "",
        passwordKeychainKey: String? = nil
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.user = user
        self.privateKeyPath = privateKeyPath
        self.passwordKeychainKey = passwordKeychainKey
    }

    public static let disabled = SSHTunnelConfig()
}