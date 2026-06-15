// ContentView.swift
import SwiftUI

struct ContentView: View {
    @State private var selectedConnection: String? = nil

    var body: some View {
        NavigationSplitView {
            ConnectionsSidebar(selection: $selectedConnection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            if let _ = selectedConnection {
                WorkspaceView()
            } else {
                EmptyStateView()
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1100, height: 700)
}
