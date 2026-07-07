// ContentView.swift
import Foundation
import OpenrowDBCore
import SwiftUI

struct ContentView: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(RefreshCoordinator.self) private var refreshCoordinator
    @Binding var showingNewConnection: Bool
    @Binding var newConnectionPreset: ConnectionFormPreset?
    @State private var selection: UUID?
    @State private var editingConnection: Connection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

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
        .background(refreshShortcut)
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
    ContentView(showingNewConnection: .constant(false), newConnectionPreset: .constant(nil))
        .environment(
            ConnectionManager(
                store: try! ConnectionStore(
                    fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("preview-connections.json")
                ),
                secrets: InMemorySecretStore()
            )
        )
        .environment(RefreshCoordinator())
        .environment(AppPreferences.shared)
        .frame(width: 1100, height: 700)
}
