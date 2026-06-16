// WorkspaceView.swift
import OpenrowDBCore
import SwiftUI

/// Detail surface for a selected connection: header bar on top, then a tab
/// strip (table / query / structure tabs), then the active tab's content.
struct WorkspaceView: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(QueryHistoryStore.self) private var history
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
            .onChange(of: isConnected) { _, connected in
                if connected {
                    tabs.restoreIfNeeded(for: connectionID, manager: manager, history: history)
                }
            }
            .onAppear {
                if isConnected {
                    tabs.restoreIfNeeded(for: connectionID, manager: manager, history: history)
                }
            }
        } else {
            PlaceholderView(
                title: "Connection unavailable",
                subtitle: "Pick a connection from the sidebar to get started.",
                systemImage: "exclamationmark.triangle",
                variant: .error
            )
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
        // GeometryReader + strict-width frame on each tab forces children
        // (especially SwiftUI Table → NSTableView) to honor the parent's
        // available width. NSTableView caches its minimum width as the sum of
        // column widths and refuses to shrink when the outer NavigationSplitView
        // sidebar animates in, so we bypass its preferred-size negotiation by
        // pinning each tab to the geometry's exact width.
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                switch tabs.selection(for: connectionID) {
                case .query(let id):
                    QueryEditorView(connectionID: connectionID, tabID: id, leadingInset: geo.safeAreaInsets.leading)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        .transition(slideTransition)
                case .table(let ref):
                    TableViewerView(connectionID: connectionID, table: ref, leadingInset: geo.safeAreaInsets.leading)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        .transition(slideTransition)
                case .structure(let id):
                    if let meta = tabs.structureMeta[id] {
                        TableStructureView(
                            connectionID: connectionID,
                            mode: meta.existingTable == nil ? .create : .edit,
                            dialect: meta.dialect,
                            database: meta.database,
                            schemas: meta.schemas,
                            defaultSchema: meta.defaultSchema,
                            existingTable: meta.existingTable,
                            onSaved: { table in
                                meta.onSaved(table)
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    tabs.closeTab(.structure(id), for: connectionID)
                                }
                            },
                            onCancel: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    tabs.closeTab(.structure(id), for: connectionID)
                                }
                            }
                        )
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        .transition(slideTransition)
                    }
                case .none:
                    PlaceholderView(
                        title: "No tab open",
                        subtitle: "Pick a table from the sidebar, or open a query with ⌘T.",
                        systemImage: "rectangle.on.rectangle"
                    )
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            // `.compositingGroup()` flattens children (including AppKit-hosted
            // NSTableView inside SwiftUI Table) into one layer so the subsequent
            // `.clipped()` actually bites during the slide transition. Without
            // it, the hosted AppKit layer composites independently and renders
            // outside the detail column — bleeding under the translucent
            // NavigationSplitView sidebar when a tab slides in/out.
            .compositingGroup()
            .clipped()
            .animation(.easeOut(duration: 0.22), value: tabs.selection(for: connectionID))
        }
        // Belt-and-suspenders: clip the GeometryReader itself so nothing
        // escapes the workspace column under any animation timing.
        .clipped()
    }

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
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
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isConnected, !connection.isReadOnly {
                DatabaseTransferMenu(
                    connectionID: connectionID,
                    dialect: connection.driver.dialect,
                    databaseName: connection.database
                )
            }

            if connection.isReadOnly {
                Label("Read-only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

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

/// Top-level tab bar for a connection's workspace. Tabs open on demand from
/// the sidebar (tables) or via ⌘T (queries); each has a close affordance.
private struct TabStrip: View {
    @Environment(WorkspaceTabsState.self) private var tabs
    let connectionID: UUID

    private var openTabs: [WorkspaceTab] {
        tabs.tabs(for: connectionID)
    }

    private var selection: WorkspaceTab? {
        tabs.selection(for: connectionID)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                GlassEffectContainer {
                    HStack(spacing: 4) {
                        ForEach(Array(openTabs.enumerated()), id: \.element.id) { index, tab in
                            TabChip(
                                tab: tab,
                                label: label(for: tab, index: index),
                                systemImage: icon(for: tab),
                                isSelected: tab == selection,
                                onSelect: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        tabs.select(tab, for: connectionID)
                                    }
                                },
                                onClose: {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        tabs.closeTab(tab, for: connectionID)
                                    }
                                }
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: openTabs.map(\.id))
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        _ = tabs.openQueryTab(for: connectionID)
                    }
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
        case .query: return "Query \(queryIndex(for: index))"
        case .table(let ref): return ref.name
        case .structure(let id):
            if let existing = tabs.structureMeta[id]?.existingTable {
                return existing.name
            }
            return "New Table"
        }
    }

    private func icon(for tab: WorkspaceTab) -> String {
        switch tab {
        case .query: return "terminal"
        case .table(let ref): return ref.kind == .view ? "eye" : "tablecells.badge.ellipsis"
        case .structure: return "square.and.pencil"
        }
    }

    /// 1-based number across query tabs only. Table and structure tabs don't
    /// participate, so "Query 1, Table foo, Query 2" reads correctly even when
    /// table tabs are interleaved.
    private func queryIndex(for absoluteIndex: Int) -> Int {
        let tabs = openTabs
        guard absoluteIndex < tabs.count else { return 1 }
        var count = 0
        for i in 0...absoluteIndex {
            if case .query = tabs[i] { count += 1 }
        }
        return max(1, count)
    }
}

private struct TabChip: View {
    let tab: WorkspaceTab
    let label: String
    let systemImage: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            chipLabel
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    @ViewBuilder
    private var chipLabel: some View {
        let inner = HStack(spacing: 6) {
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
        .contentShape(Rectangle())

        if isSelected {
            inner.glassEffect(in: .rect(cornerRadius: 6, style: .continuous))
        } else {
            inner.background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.06) : .clear)
            )
        }
    }
}
