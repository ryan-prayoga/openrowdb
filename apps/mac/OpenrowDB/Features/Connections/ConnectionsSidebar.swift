// ConnectionsSidebar.swift
import OpenrowDBCore
import SwiftUI

/// Sidebar listing saved database connections, backed by `ConnectionManager`.
struct ConnectionsSidebar: View {
    @Environment(ConnectionManager.self) private var manager
    @Binding var selection: UUID?
    @Binding var showingNewConnection: Bool
    @Binding var editingConnection: Connection?

    @State private var pendingDelete: Connection?

    var body: some View {
        List(selection: $selection) {
            Section {
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
                        .contentShape(.rect)
                        .onTapGesture(count: 2) {
                            selection = connection.id
                            Task { await manager.connect(connection.id) }
                        }
                        .contextMenu {
                            Button("Connect") {
                                Task { await manager.connect(connection.id) }
                            }
                            Button("Edit…") { editingConnection = connection }
                            Divider()
                            Button("Delete", role: .destructive) {
                                pendingDelete = connection
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Connections")
                    Spacer()
                    Button {
                        showingNewConnection = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("New Connection")
                }
            }
        }
        .listStyle(.sidebar)
        .confirmationDialog(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { connection in
            Button("Delete", role: .destructive) {
                Task { try? await manager.remove(connection) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This removes the saved connection and its stored password. This can't be undone.")
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
