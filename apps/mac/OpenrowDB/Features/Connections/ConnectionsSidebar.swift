// ConnectionsSidebar.swift
import SwiftUI

/// Sidebar listing saved database connections.
/// Phase 1 will wire this to real persistence (Keychain + UserDefaults).
struct ConnectionsSidebar: View {
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            Section("Connections") {
                Text("No connections yet")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // open new-connection sheet (Phase 1)
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
            }
        }
    }
}
