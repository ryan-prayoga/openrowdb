// WorkspaceView.swift
import OpenrowDBCore
import SwiftUI

/// Detail surface for a selected connection: header bar on top, then a tab
/// strip (Browse + N query scratchpads), then the active tab's content.
struct WorkspaceView: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(WorkspaceTabsState.self) private var tabs
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
                    TabStrip(connectionID: connectionID)
                    Divider()
                    tabContent
                } else {
                    disconnectedState
                }
            }
            .background(shortcutCatchers)
        } else {
            ContentUnavailableView("Connection unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    /// Hidden buttons whose `.keyboardShortcut` modifiers fire window-wide via
    /// the responder chain — including while `TextEditor` has focus, which
    /// `.onKeyPress` on a parent view does not handle reliably.
    private var shortcutCatchers: some View {
        ZStack {
            Button("") {
                guard isConnected else { return }
                tabs.openQueryTab(for: connectionID)
            }
            .keyboardShortcut("t", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)

            Button("") {
                guard isConnected else { return }
                tabs.closeSelectedTab(for: connectionID)
            }
            .keyboardShortcut("w", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch tabs.selection(for: connectionID) {
        case .browse:
            BrowseView(connectionID: connectionID)
        case .query(let id):
            QueryEditorView(connectionID: connectionID, tabID: id)
        case .table(let ref):
            TableViewerView(connectionID: connectionID, table: ref)
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

// MARK: - Tab strip

/// Top-level tab bar for a connection's workspace. Browse is always first and
/// non-closable; query tabs follow with close affordances and a trailing "+".
private struct TabStrip: View {
    @Environment(WorkspaceTabsState.self) private var tabs
    let connectionID: UUID

    private var openTabs: [WorkspaceTab] {
        tabs.tabs(for: connectionID)
    }

    private var selection: WorkspaceTab {
        tabs.selection(for: connectionID)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(openTabs.enumerated()), id: \.element.id) { index, tab in
                    TabChip(
                        tab: tab,
                        label: label(for: tab, index: index),
                        systemImage: icon(for: tab),
                        isSelected: tab == selection,
                        onSelect: { tabs.select(tab, for: connectionID) },
                        onClose: tab.isClosable ? { tabs.closeTab(tab, for: connectionID) } : nil
                    )
                }

                Button {
                    tabs.openQueryTab(for: connectionID)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("New Query (⌘T)")

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    private func label(for tab: WorkspaceTab, index: Int) -> String {
        switch tab {
        case .browse: return "Browse"
        case .query: return "Query \(queryIndex(for: index))"
        case .table(let ref): return ref.name
        }
    }

    private func icon(for tab: WorkspaceTab) -> String {
        switch tab {
        case .browse: return "tablecells"
        case .query: return "terminal"
        case .table(let ref): return ref.kind == .view ? "eye" : "tablecells.badge.ellipsis"
        }
    }

    /// 1-based index across query tabs only, so Browse never steals the "1".
    private func queryIndex(for absoluteIndex: Int) -> Int {
        // Browse is always at index 0; query tabs follow.
        max(1, absoluteIndex)
    }
}

private struct TabChip: View {
    let tab: WorkspaceTab
    let label: String
    let systemImage: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .imageScale(.small)
            Text(label)
                .lineLimit(1)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .padding(2)
                }
                .buttonStyle(.borderless)
                .help("Close Tab (⌘W)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
