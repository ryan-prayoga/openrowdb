// ConnectionStore.swift
import Foundation

/// Persists the list of saved connections (metadata only — passwords live in `SecretStore`).
///
/// Backed by a single JSON file. Not thread-safe by design: drive it from the
/// main actor in the app. Pure value in / value out keeps it trivially testable.
public struct ConnectionStore: Sendable {
    private let fileURL: URL

    /// - Parameter fileURL: Where to read/write the JSON. Defaults to
    ///   `~/Library/Application Support/OpenrowDB/connections.json`.
    public init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.fileURL = support
                .appendingPathComponent("OpenrowDB", isDirectory: true)
                .appendingPathComponent("connections.json", isDirectory: false)
        }
    }

    /// Load all saved connections. Returns `[]` if the file does not exist yet.
    public func load() throws -> [Connection] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [] }
        return try JSONDecoder().decode([Connection].self, from: data)
    }

    /// Overwrite the saved set, creating the parent directory if needed.
    public func save(_ connections: [Connection]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(connections)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Insert or update one connection by `id`, preserving order.
    public func upsert(_ connection: Connection) throws {
        var all = try load()
        if let index = all.firstIndex(where: { $0.id == connection.id }) {
            all[index] = connection
        } else {
            all.append(connection)
        }
        try save(all)
    }

    /// Remove a connection by `id`. No-op if absent.
    public func remove(id: UUID) throws {
        var all = try load()
        all.removeAll { $0.id == id }
        try save(all)
    }
}
