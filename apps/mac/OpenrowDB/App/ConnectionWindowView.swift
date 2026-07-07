// ConnectionWindowView.swift
import OpenrowDBCore
import SwiftUI

/// Dedicated window for a single connection — workspace only, no sidebar.
struct ConnectionWindowView: View {
  @Environment(ConnectionManager.self) private var manager
  @Environment(QueryHistoryStore.self) private var history
  @Environment(WorkspaceTabsState.self) private var tabs
  @Environment(\.controlActiveState) private var controlActiveState

  let connectionID: UUID

  @State private var refreshCoordinator = RefreshCoordinator()
  @State private var globalSearch = GlobalSearchCoordinator()
  @State private var windowToken = UUID()

  var body: some View {
    Group {
      if manager.connections.contains(where: { $0.id == connectionID }) {
        WorkspaceView(connectionID: connectionID)
      } else {
        PlaceholderView(
          title: "Connection removed",
          subtitle: "This connection was deleted from another window.",
          systemImage: "externaldrive.badge.xmark"
        )
      }
    }
    .environment(refreshCoordinator)
    .environment(globalSearch)
    .sheet(isPresented: $globalSearch.isPresented) {
      GlobalSearchView()
    }
    .task(id: connectionID) {
      guard manager.connections.contains(where: { $0.id == connectionID }) else { return }
      tabs.restoreIfNeeded(for: connectionID, manager: manager, history: history)
      if manager.status[connectionID] != .connected {
        await manager.connect(connectionID)
      }
    }
    .onAppear { wireGlobalSearch(); registerCommands() }
    .onChange(of: controlActiveState) { _, state in
      if state == .key {
        WindowCommandRouter.shared.becomeKey(token: windowToken)
      }
    }
    .onDisappear {
      WindowCommandRouter.shared.unregister(token: windowToken)
    }
    .background(refreshShortcut)
  }

  private func wireGlobalSearch() {
    globalSearch.onSelectConnection = { _ in }
    globalSearch.onOpenTable = { _, table in
      tabs.openTableTab(table, for: connectionID)
    }
    globalSearch.onSelectTab = { _, tab in
      tabs.select(tab, for: connectionID)
    }
    globalSearch.onLoadHistoryQuery = { _, sql in
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
      presentNewConnection: {},
      presentNewConnectionPreset: { _ in },
      presentSearch: { globalSearch.present() },
      presentShortcuts: {}
    )
  }

  private var refreshShortcut: some View {
    Button("") {
      guard manager.status[connectionID] == .connected else { return }
      refreshCoordinator.refresh(connectionID: connectionID)
    }
    .keyboardShortcut("r", modifiers: .command)
    .opacity(0)
    .frame(width: 0, height: 0)
    .accessibilityHidden(true)
  }
}