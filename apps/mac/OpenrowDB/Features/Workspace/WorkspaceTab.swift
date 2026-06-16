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

@MainActor
@Observable
final class WorkspaceTabsState {
    private(set) var tabsByConnection: [UUID: [WorkspaceTab]] = [:]
    private(set) var selectionByConnection: [UUID: WorkspaceTab] = [:]

    @ObservationIgnored
    private var runnersByTab: [UUID: QueryRunner] = [:]

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

    func selection(for connectionID: UUID) -> WorkspaceTab? {
        selectionByConnection[connectionID]
    }

    func select(_ tab: WorkspaceTab, for connectionID: UUID) {
        selectionByConnection[connectionID] = tab
    }

    @discardableResult
    func openQueryTab(for connectionID: UUID) -> WorkspaceTab {
        var current = tabs(for: connectionID)
        let tab = WorkspaceTab.query(UUID())
        current.append(tab)
        tabsByConnection[connectionID] = current
        selectionByConnection[connectionID] = tab
        return tab
    }

    @discardableResult
    func openTableTab(_ table: TableRef, for connectionID: UUID) -> WorkspaceTab {
        var current = tabs(for: connectionID)
        let tab = WorkspaceTab.table(table)
        if let existing = current.firstIndex(of: tab) {
            selectionByConnection[connectionID] = current[existing]
            return current[existing]
        }
        current.append(tab)
        tabsByConnection[connectionID] = current
        selectionByConnection[connectionID] = tab
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
    }

    func closeTab(_ tab: WorkspaceTab, for connectionID: UUID) {
        var current = tabs(for: connectionID)
        guard let removedIndex = current.firstIndex(of: tab) else { return }
        current.remove(at: removedIndex)
        tabsByConnection[connectionID] = current

        switch tab {
        case .query(let id): runnersByTab[id] = nil
        case .structure(let id): structureMeta[id] = nil
        case .table: break
        }

        if selectionByConnection[connectionID] == tab {
            selectionByConnection[connectionID] = current.indices.contains(removedIndex - 1)
                ? current[removedIndex - 1]
                : current.first
        }
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
            case .table: break
            }
        }
        tabsByConnection[connectionID] = nil
        selectionByConnection[connectionID] = nil
    }
}
