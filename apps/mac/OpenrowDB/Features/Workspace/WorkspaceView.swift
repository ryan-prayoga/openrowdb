// WorkspaceView.swift
import OpenrowDBCore
import SwiftUI

/// Detail surface for a selected connection. Phase 1: connect/disconnect + status.
/// Schema tree, query editor, and results grid land in Phase 2/3.
struct WorkspaceView: View {
    @Environment(ConnectionManager.self) private var manager
    let connectionID: UUID

    private var connection: Connection? {
        manager.connections.first { $0.id == connectionID }
    }

    private var status: ConnectionManager.Status {
        manager.status[connectionID] ?? .disconnected
    }

    var body: some View {
        if let connection {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(connection.name)
                        .font(.title)
                    Text("\(connection.driver.rawValue) · \(connection.user)@\(connection.host):\(connection.port)/\(connection.database)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                statusBadge

                HStack {
                    Button("Connect") {
                        Task { await manager.connect(connectionID) }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(isConnected || isConnecting)

                    Button("Disconnect") {
                        Task { await manager.disconnect(connectionID) }
                    }
                    .buttonStyle(.glass)
                    .disabled(!isConnected)
                }
                .controlSize(.large)

                Text("Schema tree + query editor land here in Phase 2.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // Selected connection was removed out from under us.
            ContentUnavailableView("Connection unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    private var isConnected: Bool { status == .connected }
    private var isConnecting: Bool { status == .connecting }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .disconnected:
            Label("Disconnected", systemImage: "circle").foregroundStyle(.secondary)
        case .connecting:
            Label("Connecting…", systemImage: "circle.dotted").foregroundStyle(.yellow)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
