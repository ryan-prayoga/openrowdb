// SecretStore.swift
import Foundation
import Security
import Synchronization

/// Stores connection passwords. Metadata (`Connection`) holds only a key into this store.
public protocol SecretStore: Sendable {
    func set(_ secret: String, for key: String) throws
    func get(_ key: String) throws -> String?
    func remove(_ key: String) throws
}

public enum SecretStoreError: Error, Sendable, Equatable {
    case unexpectedStatus(OSStatus)
    case encodingFailed
}

/// macOS Keychain-backed secret store using a generic-password item per key.
public struct KeychainSecretStore: SecretStore {
    /// Keychain service string namespacing all OpenrowDB secrets.
    public let service: String

    public init(service: String = "com.openrowdb.connection-password") {
        self.service = service
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    public func set(_ secret: String, for key: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }
        // Replace any existing item, then add fresh — simpler than SecItemUpdate's attr juggling.
        SecItemDelete(baseQuery(for: key) as CFDictionary)

        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }

    public func get(_ key: String) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    public func remove(_ key: String) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }
}

/// In-memory store for tests and previews. Not persisted.
public final class InMemorySecretStore: SecretStore {
    private let storage = Mutex<[String: String]>([:])

    public init() {}

    public func set(_ secret: String, for key: String) throws {
        storage.withLock { $0[key] = secret }
    }

    public func get(_ key: String) throws -> String? {
        storage.withLock { $0[key] }
    }

    public func remove(_ key: String) throws {
        storage.withLock { _ = $0.removeValue(forKey: key) }
    }
}
