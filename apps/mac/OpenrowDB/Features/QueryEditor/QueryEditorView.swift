// QueryEditorView.swift
import OpenrowDBCore
import SwiftUI

/// One query tab: SQL editor on top, results (per statement) on the bottom,
/// with a status line and a collapsible history inspector trailing. Keyboard:
/// ⌘Return runs, ⌘. cancels an in-flight run.
struct QueryEditorView: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(QueryHistoryStore.self) private var history
    @Environment(WorkspaceTabsState.self) private var tabs
    @Environment(RefreshCoordinator.self) private var refreshCoordinator
    let connectionID: UUID
    let tabID: UUID
    /// Leading inset for the result grid, matching the sidebar overlap so the
    /// first column doesn't render under the translucent sidebar.
    var leadingInset: CGFloat = 0

    @State private var showHistory = false
    @State private var showSnippets = false
    @State private var jumpRequest: Int = 0
    @FocusState private var editorFocused: Bool

    @State private var editorHeight: CGFloat = 240
    @State private var dragStartHeight: CGFloat?

    private static let minEditorHeight: CGFloat = 120
    private static let minResultsHeight: CGFloat = 160

    /// Pull the runner from the shared per-tab cache so SQL text and last-run
    /// results survive view recreation when the user switches tabs. Without
    /// this, every tab switch would tear down `QueryEditorView`, drop its
    /// local `@State runner`, and the next visit would start from an empty
    /// editor — surprising behaviour for any database client.
    private func runner() -> QueryRunner {
        tabs.runner(
            for: tabID,
            connectionID: connectionID,
            manager: manager,
            history: history
        )
    }

    var body: some View {
        content(runner: runner())
    }

    @ViewBuilder
    private func content(runner: QueryRunner) -> some View {
        @Bindable var runner = runner

        // HStack horizontal: main pane on the left, optional history on the
        // right. Conditional sibling intentionally avoids HSplitView — split
        // views misbehave inside an animated tab parent.
        HStack(spacing: 0) {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    editor(runner: runner)
                        .frame(height: clampedEditorHeight(for: geo.size.height))

                    horizontalResizeHandle(containerHeight: geo.size.height)

                    QueryResultsView(
                        outcomes: runner.outcomes,
                        state: runner.state,
                        leadingInset: leadingInset,
                        onJumpToError: { _ in
                            jumpRequest &+= 1
                            editorFocused = true
                        }
                    )
                    .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showHistory {
                Divider()
                QueryHistoryView(connectionID: connectionID) { sql in
                    runner.sql = sql
                    editorFocused = true
                }
                .frame(width: 280)
                .frame(maxHeight: .infinity)
            } else if showSnippets {
                Divider()
                QuerySnippetsView(
                    connectionID: connectionID,
                    currentSQL: { runner.sql }
                ) { sql in
                    runner.sql = sql
                    editorFocused = true
                }
                .frame(width: 280)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: refreshCoordinator.signal(for: connectionID)) { _, _ in
            Task { await runner.catalog.refresh() }
        }
    }

    private func clampedEditorHeight(for containerHeight: CGFloat) -> CGFloat {
        let maxAllowed = max(Self.minEditorHeight, containerHeight - Self.minResultsHeight - 6)
        return min(max(editorHeight, Self.minEditorHeight), maxAllowed)
    }

    private func horizontalResizeHandle(containerHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 6)
            .overlay(Divider(), alignment: .center)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartHeight == nil { dragStartHeight = editorHeight }
                        let proposed = (dragStartHeight ?? editorHeight) + value.translation.height
                        let maxAllowed = max(Self.minEditorHeight, containerHeight - Self.minResultsHeight - 6)
                        editorHeight = min(max(proposed, Self.minEditorHeight), maxAllowed)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }

    // MARK: - Editor

    @ViewBuilder
    private func editor(runner: QueryRunner) -> some View {
        @Bindable var runner = runner

        VStack(spacing: 0) {
            toolbar(runner: runner)
            Divider()
            CodeEditor(
                text: $runner.sql,
                dialect: dialect,
                schema: runner.catalog.snapshot,
                onSubmit: { runner.run() },
                errorPosition: firstErrorPosition(in: runner.outcomes),
                jumpRequest: jumpRequest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .focused($editorFocused)
            .onAppear {
                editorFocused = true
                Task { await runner.catalog.refresh() }
            }
            Divider()
            statusBar(runner: runner)
        }
    }

    private var dialect: SQLDialect {
        manager.connections.first(where: { $0.id == connectionID })?.driver.dialect ?? .postgres
    }

    private func toolbar(runner: QueryRunner) -> some View {
        HStack(spacing: 8) {
            Button {
                runner.run()
            } label: {
                Label {
                    Text(isRunning(runner.state) ? "Running…" : "Run")
                } icon: {
                    Image(systemName: isRunning(runner.state) ? "hourglass" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(isRunning(runner.state) || runner.sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if isRunning(runner.state) {
                Button {
                    runner.cancel()
                } label: {
                    Label("Cancel", systemImage: "stop.fill")
                }
                .buttonStyle(.glass)
                .keyboardShortcut(".", modifiers: .command)
                .transition(.opacity)
            }

            Button {
                runner.sql = SQLFormatter.format(runner.sql, dialect: dialect)
            } label: {
                Label("Format", systemImage: "text.alignleft")
            }
            .buttonStyle(.glass)
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .help("Format SQL (⌘⇧F)")

            Spacer()

            ExportButton(outcomes: runner.outcomes)

            Toggle(isOn: $showSnippets) {
                Label("Snippets", systemImage: "bookmark")
            }
            .toggleStyle(.button)
            .help("Saved query snippets")
            .onChange(of: showSnippets) { _, on in
                if on { showHistory = false }
            }

            Toggle(isOn: $showHistory) {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .toggleStyle(.button)
            .help("Show query history")
            .onChange(of: showHistory) { _, on in
                if on { showSnippets = false }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.18), value: isRunning(runner.state))
    }

    private func statusBar(runner: QueryRunner) -> some View {
        HStack(spacing: 10) {
            switch runner.state {
            case .idle:
                Text("Ready").foregroundStyle(.secondary)
            case .running(let progress):
                ProgressView().controlSize(.small)
                Text("Running \(progress)").foregroundStyle(.secondary)
            case .finished:
                summary(runner.outcomes)
            }
            Spacer()
            Text("\(charCount(runner.sql)) chars · \(lineCount(runner.sql)) lines")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func summary(_ outcomes: [QueryRunner.StatementOutcome]) -> some View {
        let failures = outcomes.filter(\.didFail).count
        let totalDuration = outcomes.reduce(0) { $0 + $1.durationMs }
        let totalRows = outcomes.reduce(0) { $0 + ($1.result?.rows.count ?? 0) }

        return HStack(spacing: 8) {
            if failures > 0 {
                Label("\(failures) failed", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            } else {
                Label("OK", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            Text("\(outcomes.count) statement\(outcomes.count == 1 ? "" : "s") · \(totalRows) rows · \(totalDuration) ms")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func isRunning(_ state: QueryRunner.State) -> Bool {
        if case .running = state { return true }
        return false
    }

    private func charCount(_ string: String) -> Int { string.count }

    private func lineCount(_ string: String) -> Int {
        string.isEmpty ? 0 : string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    private func firstErrorPosition(in outcomes: [QueryRunner.StatementOutcome]) -> Int? {
        outcomes.first(where: { $0.errorPosition != nil })?.errorPosition
    }
}
