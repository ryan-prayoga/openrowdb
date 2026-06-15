// WorkspaceView.swift
import OpenrowDBCore
import SwiftUI

/// Detail surface for a selected connection: a compact status/connect bar on top,
/// and (once connected) the schema browser below.
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
            VStack(spacing: 0) {
                header(connection)
                Divider()

                if isConnected {
                    BrowseView(connectionID: connectionID)
                } else {
                    disconnectedState
                }
            }
        } else {
            ContentUnavailableView("Connection unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    // MARK: - Header

    private func header(_ connection: Connection) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(connection.name)
                    .font(.headline)
                Text("\(connection.driver.rawValue) · \(connection.user)@\(connection.host):\(connection.port)/\(connection.database)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge

            if isConnected {
                Button("Disconnect") {
                    Task { await manager.disconnect(connectionID) }
                }
                .buttonStyle(.glass)
            } else {
                Button("Connect") {
                    Task { await manager.connect(connectionID) }
                }
                .buttonStyle(.glassProminent)
                .disabled(isConnecting)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var disconnectedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isConnecting ? "Connecting…" : "Not connected")
                .font(.title3)
            if case .failed(let message) = status {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status

    private var isConnected: Bool { status == .connected }
    private var isConnecting: Bool { status == .connecting }

    private var statusBadge: some View {
        Group {
            switch status {
            case .disconnected:
                Label("Disconnected", systemImage: "circle").foregroundStyle(.secondary)
            case .connecting:
                Label("Connecting…", systemImage: "circle.dotted").foregroundStyle(.yellow)
            case .connected:
                Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
    }
}
