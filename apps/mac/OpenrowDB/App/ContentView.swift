// ContentView.swift
import Foundation
import OpenrowDBCore
import SwiftUI

struct ContentView: View {
    @Environment(ConnectionManager.self) private var manager
    @Binding var showingNewConnection: Bool
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            ConnectionsSidebar(
                selection: $selection,
                showingNewConnection: $showingNewConnection
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            if let selection, manager.connections.contains(where: { $0.id == selection }) {
                WorkspaceView(connectionID: selection)
            } else {
                EmptyStateView(showingNewConnection: $showingNewConnection)
            }
        }
        .sheet(isPresented: $showingNewConnection) {
            NewConnectionSheet()
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
