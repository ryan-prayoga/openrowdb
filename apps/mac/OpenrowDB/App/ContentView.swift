// ContentView.swift
import Foundation
import OpenrowDBCore
import SwiftUI

struct ContentView: View {
    @Environment(ConnectionManager.self) private var manager
    @Binding var showingNewConnection: Bool
    @State private var selection: UUID?
    @State private var editingConnection: Connection?

    var body: some View {
        NavigationSplitView {
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
            .navigationSplitViewColumnWidth(min: 640, ideal: 820)
        }
        .sheet(isPresented: $showingNewConnection) {
            ConnectionSheet()
        }
        .sheet(item: $editingConnection) { connection in
            ConnectionSheet(existing: connection)
        }
    }
}

#Preview {
    ContentView(showingNewConnection: .constant(false))
        .environment(
            ConnectionManager(
                store: try! ConnectionStore(
                    fileURL: FileManager.default.temporaryDirectory
                        .appendingPathComponent("preview-connections.json")
                ),
                secrets: InMemorySecretStore()
            )
        )
        .frame(width: 1100, height: 700)
}
