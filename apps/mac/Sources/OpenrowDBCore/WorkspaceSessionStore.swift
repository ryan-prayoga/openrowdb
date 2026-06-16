// WorkspaceSessionStore.swift
import Foundation

/// One persisted workspace tab. Structure tabs are intentionally omitted —
/// they carry UI closures and are ephemeral.
public enum PersistedWorkspaceTab: Sendable, Equatable {
    case query(id: UUID, sql: String)
    case table(ref: TableRef, filterColumn: String?, filterValue: String?)

    public var tabKey: String {
        switch self {
        case .query(let id, _): return "query:\(id.uuidString)"
        case .table(let ref, _, _): return "table:\(ref.id)"
        }
    }
}

extension PersistedWorkspaceTab: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, id, sql, ref, filterColumn, filterValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "query":
            self = .query(
                id: try container.decode(UUID.self, forKey: .id),
                sql: try container.decode(String.self, forKey: .sql)
            )
        case "table":
            self = .table(
                ref: try container.decode(TableRef.self, forKey: .ref),
                filterColumn: try container.decodeIfPresent(String.self, forKey: .filterColumn),
                filterValue: try container.decodeIfPresent(String.self, forKey: .filterValue)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown persisted tab kind: \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .query(let id, let sql):
            try container.encode("query", forKey: .kind)
            try container.encode(id, forKey: .id)
            try container.encode(sql, forKey: .sql)
        case .table(let ref, let filterColumn, let filterValue):
            try container.encode("table", forKey: .kind)
            try container.encode(ref, forKey: .ref)
            try container.encodeIfPresent(filterColumn, forKey: .filterColumn)
            try container.encodeIfPresent(filterValue, forKey: .filterValue)
        }
    }
}

/// Saved tab strip + SQL text for one connection.
public struct WorkspaceSessionData: Sendable, Equatable, Codable {
    public var tabs: [PersistedWorkspaceTab]
    public var selectedTabKey: String?

    public init(tabs: [PersistedWorkspaceTab] = [], selectedTabKey: String? = nil) {
        self.tabs = tabs
        self.selectedTabKey = selectedTabKey
    }
}

/// Persists open workspace tabs and query SQL across app restarts.
public struct WorkspaceSessionStore: Sendable {
    private let fileURL: URL

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
                .appendingPathComponent("workspace.json", isDirectory: false)
        }
    }

    public func loadAll() throws -> [UUID: WorkspaceSessionData] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return [:] }
        let raw = try JSONDecoder().decode([String: WorkspaceSessionData].self, from: data)
        var result: [UUID: WorkspaceSessionData] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key) {
                result[id] = value
            }
        }
        return result
    }

    public func load(for connectionID: UUID) throws -> WorkspaceSessionData? {
        try loadAll()[connectionID]
    }

    public func save(_ data: WorkspaceSessionData, for connectionID: UUID) throws {
        var all = try loadAll()
        if data.tabs.isEmpty {
            all.removeValue(forKey: connectionID)
        } else {
            all[connectionID] = data
        }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoded = Dictionary(uniqueKeysWithValues: all.map { ($0.key.uuidString, $0.value) })
        let bytes = try JSONEncoder().encode(encoded)
        try bytes.write(to: fileURL, options: .atomic)
    }
}