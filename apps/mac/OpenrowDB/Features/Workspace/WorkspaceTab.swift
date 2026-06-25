// WorkspaceTab.swift
import Foundation
import Observation
import OpenrowDBCore
import SwiftUI

enum WorkspaceTab: Hashable, Identifiable {
    case query(UUID)
    case table(TableRef)
    case structure(UUID)

    var id: String {
        switch self {
        case .query(let uuid): return "query:\(uuid.uuidString)"
        case .table(let ref): return "table:\(ref.id)"
        case .structure(let uuid): return "structure:\(uuid.uuidString)"
        }
    }
}

struct TableTabFilter: Equatable, Sendable {
    let column: String
    let value: String
}

@MainActor
@Observable
final class WorkspaceTabsState {
    private(set) var tabsByConnection: [UUID: [WorkspaceTab]] = [:]
    private(set) var selectionByConnection: [UUID: WorkspaceTab] = [:]

    @ObservationIgnored
    private var runnersByTab: [UUID: QueryRunner] = [:]

    @ObservationIgnored
    private var tableFilters: [String: TableTabFilter] = [:]

    @ObservationIgnored
    private var restoredConnections: Set<UUID> = []

    /// Debounce generation per connection. Newer schedules bump the counter so
    /// older sleep tasks exit without persisting — never cancel a sleeping Task
    /// (Task.cancel during Task.sleep aborts on macOS 26 / Swift 6).
    @ObservationIgnored
    private var persistGeneration: [UUID: UInt64] = [:]

    @ObservationIgnored
    var sessionStore: WorkspaceSessionStore?

    // Structure tab metadata lives off the observable graph (closures are not
    // observable-compatible) but is managed alongside tab open/close.
    struct StructureTabMeta {
        let dialect: SQLDialect
        let database: String
        let schemas: [String]
        let defaultSchema: String
        let existingTable: TableRef?
        let onSaved: (TableRef) -> Void
    }
    @ObservationIgnored
    private(set) var structureMeta: [UUID: StructureTabMeta] = [:]

    func runner(
        for tabID: UUID,
        connectionID: UUID,
        manager: ConnectionManager,
        history: QueryHistoryStore
    ) -> QueryRunner {
        if let existing = runnersByTab[tabID] { return existing }
        let runner = QueryRunner(
            connectionID: connectionID,
            tabID: tabID,
            manager: manager,
            history: history
        )
        runnersByTab[tabID] = runner
        return runner
    }

    func tabs(for connectionID: UUID) -> [WorkspaceTab] {
        tabsByConnection[connectionID] ?? []
    }

    /// Whether a query tab holds SQL that hasn't been run yet (or was edited
    /// since its last run) — drives the unsaved dot in the tab strip. Reads the
    /// runner's observable `sql`/`lastRunSQL`, so the dot updates live as the
    /// user types. Returns false when no runner exists for the tab yet.
    func isQueryDirty(_ tabID: UUID) -> Bool {
        runnersByTab[tabID]?.isDirty ?? false
    }

    func selection(for connectionID: UUID) -> WorkspaceTab? {
        selectionByConnection[connectionID]
    }

    func select(_ tab: WorkspaceTab, for connectionID: UUID) {
        selectionByConnection[connectionID] = tab
        schedulePersist(for: connectionID)
    }

    func tableFilter(for table: TableRef) -> TableTabFilter? {
        tableFilters[table.id]
    }

    /// Restore tabs from disk once per connection per app launch.
    func restoreIfNeeded(
        for connectionID: UUID,
        manager: ConnectionManager,
        history: QueryHistoryStore
    ) {
        guard !restoredConnections.contains(connectionID) else { return }
        restoredConnections.insert(connectionID)
        guard tabs(for: connectionID).isEmpty,
              let store = sessionStore,
              let data = try? store.load(for: connectionID),
              !data.tabs.isEmpty else { return }

        var restored: [WorkspaceTab] = []
        for persisted in data.tabs {
            switch persisted {
            case .query(let id, let sql):
                restored.append(.query(id))
                let runner = self.runner(for: id, connectionID: connectionID, manager: manager, history: history)
                runner.sql = sql
            case .table(let ref, let filterColumn, let filterValue):
                restored.append(.table(ref))
                if let filterColumn, let filterValue, !filterColumn.isEmpty, !filterValue.isEmpty {
                    tableFilters[ref.id] = TableTabFilter(column: filterColumn, value: filterValue)
                }
            }
        }
        tabsByConnection[connectionID] = restored
        if let key = data.selectedTabKey,
           let match = restored.first(where: { $0.id == key }) {
            selectionByConnection[connectionID] = match
        } else {
            selectionByConnection[connectionID] = restored.first
        }
    }

    func schedulePersist(for connectionID: UUID) {
        let generation = (persistGeneration[connectionID] ?? 0) + 1
        persistGeneration[connectionID] = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in
            guard let self, self.persistGeneration[connectionID] == generation else { return }
            self.persistNow(for: connectionID)
        }
    }

    func persistNow(for connectionID: UUID) {
        guard let store = sessionStore else { return }
        let tabs = tabs(for: connectionID)
        var persisted: [PersistedWorkspaceTab] = []
        for tab in tabs {
            switch tab {
            case .query(let id):
                let sql = runnersByTab[id]?.sql ?? ""
                persisted.append(.query(id: id, sql: sql))
            case .table(let ref):
                let filter = tableFilters[ref.id]
                persisted.append(.table(ref: ref, filterColumn: filter?.column, filterValue: filter?.value))
            case .structure:
                continue
            }
        }
        let data = WorkspaceSessionData(
            tabs: persisted,
            selectedTabKey: selection(for: connectionID)?.id
        )
        try? store.save(data, for: connectionID)
    }

    @discardableResult
    func openQueryTab(for connectionID: UUID) -> WorkspaceTab {
        var current = tabs(for: connectionID)
        let tab = WorkspaceTab.query(UUID())
        current.append(tab)
        tabsByConnection[connectionID] = current
        selectionByConnection[connectionID] = tab
        schedulePersist(for: connectionID)
        return tab
    }

    @discardableResult
    func openTableTab(
        _ table: TableRef,
        for connectionID: UUID,
        filterColumn: String? = nil,
        filterValue: String? = nil
    ) -> WorkspaceTab {
        if let filterColumn, let filterValue, !filterColumn.isEmpty, !filterValue.isEmpty {
            tableFilters[table.id] = TableTabFilter(column: filterColumn, value: filterValue)
        }
        var current = tabs(for: connectionID)
        let tab = WorkspaceTab.table(table)
        if let existing = current.firstIndex(of: tab) {
            selectionByConnection[connectionID] = current[existing]
            schedulePersist(for: connectionID)
            return current[existing]
        }
        current.append(tab)
        tabsByConnection[connectionID] = current
        selectionByConnection[connectionID] = tab
        schedulePersist(for: connectionID)
        return tab
    }

    func openStructureTab(
        for connectionID: UUID,
        dialect: SQLDialect,
        database: String,
        schemas: [String] = [],
        defaultSchema: String = "public",
        existingTable: TableRef? = nil,
        onSaved: @escaping (TableRef) -> Void
    ) {
        let tabID = UUID()
        structureMeta[tabID] = StructureTabMeta(
            dialect: dialect,
            database: database,
            schemas: schemas,
            defaultSchema: defaultSchema,
            existingTable: existingTable,
            onSaved: onSaved
        )
        var current = tabs(for: connectionID)
        current.append(.structure(tabID))
        tabsByConnection[connectionID] = current
        selectionByConnection[connectionID] = .structure(tabID)
        schedulePersist(for: connectionID)
    }

    func closeTab(_ tab: WorkspaceTab, for connectionID: UUID) {
        var current = tabs(for: connectionID)
        guard let removedIndex = current.firstIndex(of: tab) else { return }
        current.remove(at: removedIndex)
        tabsByConnection[connectionID] = current

        switch tab {
        case .query(let id): runnersByTab[id] = nil
        case .structure(let id): structureMeta[id] = nil
        case .table(let ref):
            tableFilters[ref.id] = nil
        }

        if selectionByConnection[connectionID] == tab {
            selectionByConnection[connectionID] = current.indices.contains(removedIndex - 1)
                ? current[removedIndex - 1]
                : current.first
        }
        schedulePersist(for: connectionID)
    }

    func closeSelectedTab(for connectionID: UUID) {
        guard let selected = selection(for: connectionID) else { return }
        closeTab(selected, for: connectionID)
    }

    func reset(for connectionID: UUID) {
        for tab in tabsByConnection[connectionID] ?? [] {
            switch tab {
            case .query(let id): runnersByTab[id] = nil
            case .structure(let id): structureMeta[id] = nil
            case .table(let ref): tableFilters[ref.id] = nil
            }
        }
        tabsByConnection[connectionID] = nil
        selectionByConnection[connectionID] = nil
        schedulePersist(for: connectionID)
    }
}
