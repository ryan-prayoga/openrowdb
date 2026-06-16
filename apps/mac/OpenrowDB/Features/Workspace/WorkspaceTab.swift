// WorkspaceTab.swift
import Foundation
import Observation
import OpenrowDBCore
import SwiftUI

/// One tab inside a connection's workspace. Browse is the default, non-closable
/// tab; query tabs are user-created scratchpads with independent SQL + results;
/// table tabs view one specific table's rows (opened from Browse via context menu).
enum WorkspaceTab: Hashable, Identifiable {
    case browse
    case query(UUID)
    case table(TableRef)

    var id: String {
        switch self {
        case .browse: return "browse"
        case .query(let uuid): return "query:\(uuid.uuidString)"
        case .table(let ref): return "table:\(ref.id)"
        }
    }

    var isClosable: Bool {
        if case .browse = self { return false }
        return true
    }
}

/// Per-connection tab state. Each open connection gets its own bag of tabs so
/// switching between connections preserves whatever was open in each.
@MainActor
@Observable
final class WorkspaceTabsState {
    private(set) var tabsByConnection: [UUID: [WorkspaceTab]] = [:]
    private(set) var selectionByConnection: [UUID: WorkspaceTab] = [:]

    func tabs(for connectionID: UUID) -> [WorkspaceTab] {
        if let existing = tabsByConnection[connectionID] { return existing }
        // First time we see this connection — seed with the Browse tab.
        let seeded: [WorkspaceTab] = [.browse]
        tabsByConnection[connectionID] = seeded
        selectionByConnection[connectionID] = .browse
        return seeded
    }

    func selection(for connectionID: UUID) -> WorkspaceTab {
        _ = tabs(for: connectionID)
        return selectionByConnection[connectionID] ?? .browse
    }

    func select(_ tab: WorkspaceTab, for connectionID: UUID) {
        _ = tabs(for: connectionID)
        selectionByConnection[connectionID] = tab
    }

    /// Open a new query tab and select it. Returns the new tab so callers can
    /// reference it (e.g. to focus the editor).
    @discardableResult
    func openQueryTab(for connectionID: UUID) -> WorkspaceTab {
        var current = tabs(for: connectionID)
        let tab = WorkspaceTab.query(UUID())
        current.append(tab)
        tabsByConnection[connectionID] = current
        selectionByConnection[connectionID] = tab
        return tab
    }

    /// Open a table viewer tab for the given table. If a tab for this table is
    /// already open, just select it instead of creating a duplicate.
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

    /// Close a tab. Browse is never closable. When the currently selected tab is
    /// removed, selection falls back to the previous tab (or Browse).
    func closeTab(_ tab: WorkspaceTab, for connectionID: UUID) {
        guard tab.isClosable else { return }
        var current = tabs(for: connectionID)
        guard let removedIndex = current.firstIndex(of: tab) else { return }
        current.remove(at: removedIndex)
        tabsByConnection[connectionID] = current

        if selectionByConnection[connectionID] == tab {
            let fallback = current.indices.contains(removedIndex - 1)
                ? current[removedIndex - 1]
                : current.first ?? .browse
            selectionByConnection[connectionID] = fallback
        }
    }

    /// Close the currently selected tab, if any (no-op for Browse).
    func closeSelectedTab(for connectionID: UUID) {
        closeTab(selection(for: connectionID), for: connectionID)
    }

    /// Drop all state for a connection (e.g. on disconnect-and-remove).
    func reset(for connectionID: UUID) {
        tabsByConnection[connectionID] = nil
        selectionByConnection[connectionID] = nil
    }
}
