// ContentView.swift
import Foundation
import OpenrowDBCore
import SwiftUI

struct ContentView: View {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(ConnectionManager.self) private var manager
    @Environment(QueryHistoryStore.self) private var history
    @Environment(WorkspaceTabsState.self) private var tabs

    @State private var selection: UUID?
    @State private var editingConnection: Connection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showingNewConnection = false
    @State private var newConnectionPreset: ConnectionFormPreset?
    @State private var showingShortcuts = false
    @State private var globalSearch = GlobalSearchCoordinator()
    @State private var refreshCoordinator = RefreshCoordinator()
    @State private var windowToken = UUID()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConnectionsSidebar(
                selection: $selection,
                showingNewConnection: $showingNewConnection,
                editingConnection: $editingConnection
            )
            // Set width here, NOT via .frame(minWidth:) on the split view — a global
            // frame constraint causes the sidebar collapse animation to stutter.
            // (Apple DTS: developer.apple.com/forums/thread/775713)
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            Group {
                if let selection, manager.connections.contains(where: { $0.id == selection }) {
                    WorkspaceView(connectionID: selection)
                } else {
                    EmptyStateView(showingNewConnection: $showingNewConnection)
                }
            }
            .navigationSplitViewColumnWidth(min: 480, ideal: 820)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingNewConnection, onDismiss: { newConnectionPreset = nil }) {
            ConnectionSheet(preset: newConnectionPreset)
        }
        .sheet(item: $editingConnection) { connection in
            ConnectionSheet(existing: connection)
        }
        .sheet(isPresented: $showingShortcuts) {
            ShortcutsHelpView()
        }
        .sheet(isPresented: $globalSearch.isPresented) {
            GlobalSearchView()
        }
        .environment(refreshCoordinator)
        .environment(globalSearch)
        .background(refreshShortcut)
        .onAppear {
            wireGlobalSearch()
            registerCommands()
        }
        .onChange(of: controlActiveState) { _, state in
            if state == .key {
                WindowCommandRouter.shared.becomeKey(token: windowToken)
            }
        }
        .onDisappear {
            WindowCommandRouter.shared.unregister(token: windowToken)
        }
    }

    private func wireGlobalSearch() {
        globalSearch.onSelectConnection = { selection = $0 }
        globalSearch.onOpenTable = { connectionID, table in
            tabs.openTableTab(table, for: connectionID)
        }
        globalSearch.onSelectTab = { connectionID, tab in
            tabs.select(tab, for: connectionID)
        }
        globalSearch.onLoadHistoryQuery = { connectionID, sql in
            let tab = tabs.openQueryTab(for: connectionID)
            if case .query(let id) = tab {
                let runner = tabs.runner(
                    for: id,
                    connectionID: connectionID,
                    manager: manager,
                    history: history
                )
                runner.sql = sql
            }
        }
    }

    private func registerCommands() {
        WindowCommandRouter.shared.register(
            token: windowToken,
            presentNewConnection: { showingNewConnection = true },
            presentNewConnectionPreset: { preset in
                newConnectionPreset = preset
                showingNewConnection = true
            },
            presentSearch: { globalSearch.present() },
            presentShortcuts: { showingShortcuts = true }
        )
    }

    /// Window-wide ⌘R — fires via the responder chain even when the SQL editor
    /// or a hosted NSTableView has focus.
    private var refreshShortcut: some View {
        Button("") {
            guard let selection,
                  manager.status[selection] == .connected else { return }
            refreshCoordinator.refresh(connectionID: selection)
        }
        .keyboardShortcut("r", modifiers: .command)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

#Preview {
    ContentView()
        .environment(
            ConnectionManager(
                store: try! ConnectionStore(
                    fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("preview-connections.json")
                ),
                secrets: InMemorySecretStore()
            )
        )
        .environment(WorkspaceTabsState())
        .environment(try! QueryHistoryStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("preview-history.sqlite")
        ))
        .environment(AppPreferences.shared)
        .frame(width: 1100, height: 700)
}