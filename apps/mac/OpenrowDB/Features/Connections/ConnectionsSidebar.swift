// ConnectionsSidebar.swift
import OpenrowDBCore
import SwiftUI

/// Sidebar listing saved database connections, backed by `ConnectionManager`.
struct ConnectionsSidebar: View {
    @Environment(ConnectionManager.self) private var manager
    @Binding var selection: UUID?
    @Binding var showingNewConnection: Bool

    var body: some View {
        List(selection: $selection) {
            Section("Connections") {
                if manager.connections.isEmpty {
                    Text("No connections yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(manager.connections) { connection in
                        ConnectionRow(
                            connection: connection,
                            status: manager.status[connection.id] ?? .disconnected
                        )
                        .tag(connection.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                Task { try? await manager.remove(connection) }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewConnection = true
                } label: {
                    Label("New Connection", systemImage: "plus")
                }
            }
        }
    }
}

private struct ConnectionRow: View {
    let connection: Connection
    let status: ConnectionManager.Status

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                Text("\(connection.driver.rawValue) · \(connection.host)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusDot: View {
    let status: ConnectionManager.Status

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(label)
    }

    private var color: Color {
        switch status {
        case .disconnected: .secondary
        case .connecting: .yellow
        case .connected: .green
        case .failed: .red
        }
    }

    private var label: String {
        switch status {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .failed(let message): "Failed: \(message)"
        }
    }
}
