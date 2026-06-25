// QueryEditorView.swift
import AppKit
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

    @State private var showHistory = false
    @State private var showSnippets = false
    @State private var showExplain = false
    @State private var explainSQL = ""
    @State private var explainResult: QueryResult?
    @State private var explainError: String?
    @State private var explainLoading = false
    @State private var jumpRequest: Int = 0
    @State private var cursor = CodeEditor.CursorPosition()
    @State private var databases: [String] = []
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
                        .frame(height: effectiveEditorHeight(container: geo.size.height, runner: runner))

                    horizontalResizeHandle(containerHeight: geo.size.height)

                    QueryResultsView(
                        outcomes: runner.outcomes,
                        state: runner.state,
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
        .onChange(of: runner.sql) { _, _ in
            tabs.schedulePersist(for: connectionID)
        }
        .sheet(isPresented: $showExplain) {
            ExplainPlanView(
                sql: explainSQL,
                result: explainResult,
                error: explainError,
                loading: explainLoading
            )
        }
    }

    private func clampedEditorHeight(for containerHeight: CGFloat) -> CGFloat {
        let maxAllowed = max(Self.minEditorHeight, containerHeight - Self.minResultsHeight - 6)
        return min(max(editorHeight, Self.minEditorHeight), maxAllowed)
    }

    /// While a tab has no results to show, the editor takes the lion's share of
    /// the pane (so the void below shrinks to a tidy getting-started strip).
    /// Once a run produces results, it falls back to the user's chosen height so
    /// the grid gets room. A manual drag larger than the default still wins.
    private func effectiveEditorHeight(container: CGFloat, runner: QueryRunner) -> CGFloat {
        // Before the geometry resolves, hand back the stored height rather than a
        // height derived from a zero container — a transient zero-height pass can
        // make the hosted NSTextView cache a broken (narrow) layout.
        guard container > 0 else { return editorHeight }
        // Expand whenever there are no results to show (including while a query
        // is still running) so the only height change is the single shrink when
        // results actually land.
        guard !runner.hasResults else {
            return clampedEditorHeight(for: container)
        }
        let maxAllowed = max(Self.minEditorHeight, container - Self.minResultsHeight - 6)
        let target = max(editorHeight, container * 0.62)
        return min(max(target, Self.minEditorHeight), maxAllowed)
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
                onSubmit: {
                    // ⌘↩ runs the selection or current statement; ⌘⇧↩ runs all.
                    if NSEvent.modifierFlags.contains(.shift) {
                        runner.run()
                    } else {
                        smartRun(runner)
                    }
                },
                errorPosition: firstErrorPosition(in: runner.outcomes),
                jumpRequest: jumpRequest,
                onCursorChange: { cursor = $0 }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The hosted NSScrollView's line-number ruler composites its drawing
            // on a layer that isn't clipped to this SwiftUI frame, so the
            // gutter's vertical edge bled up behind the toolbar and down behind
            // the results pane as a full-height seam. compositingGroup() flattens
            // the AppKit layer so clipped() actually bites (same trick as the
            // tab slide in WorkspaceView).
            .compositingGroup()
            .clipped()
            .focused($editorFocused)
            .onAppear {
                editorFocused = true
                Task { await runner.catalog.refresh() }
                Task { databases = (try? await manager.databases(on: connectionID)) ?? [] }
            }
            Divider()
            statusBar(runner: runner)
        }
    }

    private var dialect: SQLDialect {
        manager.connections.first(where: { $0.id == connectionID })?.driver.dialect ?? .postgres
    }

    private func toolbar(runner: QueryRunner) -> some View {
        let running = isRunning(runner.state)
        let blank = isBlank(runner.sql)
        return HStack(spacing: 8) {
            Menu {
                Button("Run Current Statement") { runCurrent(runner) }
                Button("Run Selection") { runSelection(runner) }
                    .disabled(cursor.selectionLength == 0)
                Divider()
                Button("Run All Statements") { runner.run() }
            } label: {
                Label {
                    Text(running ? "Running…" : "Run")
                } icon: {
                    Image(systemName: running ? "hourglass" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
            } primaryAction: {
                smartRun(runner)
            }
            .menuStyle(.button)
            .buttonStyle(.glassProminent)
            .fixedSize()
            .disabled(running || blank)
            .help("Run selection or current statement (⌘↩) · Run all (⇧⌘↩)")

            if running {
                Button {
                    runner.cancel()
                } label: {
                    Image(systemName: "stop.fill").frame(width: 16, height: 16)
                }
                .buttonStyle(.glass)
                .keyboardShortcut(".", modifiers: .command)
                .help("Cancel run (⌘.)")
                .accessibilityLabel("Cancel")
                .transition(.opacity)
            }

            iconButton("text.alignleft", help: "Format SQL (⌘⇧F)", accessibility: "Format") {
                runner.sql = SQLFormatter.format(runner.sql, dialect: dialect)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(blank)

            iconButton("list.bullet.rectangle", help: "Explain plan for the first statement", accessibility: "Explain") {
                runExplain(runner: runner)
            }
            .disabled(running || blank)

            databaseMenu(runner: runner)

            if manager.isReadOnly(connectionID) {
                Label("Read-only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            ExportButton(outcomes: runner.outcomes)

            Toggle(isOn: $showSnippets) {
                Image(systemName: "bookmark").frame(width: 16, height: 16)
            }
            .toggleStyle(.button)
            .help("Saved query snippets")
            .accessibilityLabel("Snippets")
            .onChange(of: showSnippets) { _, on in
                if on { showHistory = false }
            }

            Toggle(isOn: $showHistory) {
                Image(systemName: "clock.arrow.circlepath").frame(width: 16, height: 16)
            }
            .toggleStyle(.button)
            .help("Show query history")
            .accessibilityLabel("History")
            .onChange(of: showHistory) { _, on in
                if on { showSnippets = false }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.18), value: running)
    }

    /// Uniform 16×16 glass icon button, matching the table action-bar sizing so
    /// `.glass` padding stays consistent across every icon-only control.
    private func iconButton(
        _ systemName: String,
        help: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName).frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .help(help)
        .accessibilityLabel(accessibility)
    }

    /// Database this query tab targets. Defaults to the connection's database;
    /// the picker lets the user point a tab at any database on the server so
    /// autocomplete and runs match what they're browsing in the sidebar tree.
    private func databaseMenu(runner: QueryRunner) -> some View {
        let current = currentDatabase(runner)
        return Menu {
            ForEach(databases, id: \.self) { db in
                Button {
                    runner.useDatabase(db)
                } label: {
                    if db == current {
                        Label(db, systemImage: "checkmark")
                    } else {
                        Text(db)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cylinder.split.1x2").frame(width: 16, height: 16)
                Text(current).lineLimit(1)
            }
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .help("Database for this query tab")
        .accessibilityLabel("Database: \(current)")
    }

    private var connectionDatabase: String? {
        manager.connections.first { $0.id == connectionID }?.database
    }

    private func currentDatabase(_ runner: QueryRunner) -> String {
        runner.database ?? connectionDatabase ?? "—"
    }

    private func statusBar(runner: QueryRunner) -> some View {
        HStack(spacing: 10) {
            if let driverLabel {
                Text(driverLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: .capsule)
            }
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
            if cursor.selectionLength > 0 {
                Text("\(cursor.selectionLength) selected").foregroundStyle(.tertiary)
                Text("·").foregroundStyle(.quaternary)
            }
            Text("Ln \(cursor.line), Col \(cursor.column)")
                .foregroundStyle(.tertiary)
                .monospacedDigit()
            Text("·").foregroundStyle(.quaternary)
            Text("\(charCount(runner.sql)) chars · \(lineCount(runner.sql)) lines")
                .foregroundStyle(.tertiary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var driverLabel: String? {
        manager.connections.first { $0.id == connectionID }?.driver.rawValue
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

    private func isBlank(_ sql: String) -> Bool {
        sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func charCount(_ string: String) -> Int { string.count }

    private func lineCount(_ string: String) -> Int {
        string.isEmpty ? 0 : string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }

    private func firstErrorPosition(in outcomes: [QueryRunner.StatementOutcome]) -> Int? {
        outcomes.first(where: { $0.errorPosition != nil })?.errorPosition
    }

    // MARK: - Run targeting

    /// ⌘↩ behaviour: run the selection if there is one, else the statement under
    /// the caret, else fall back to the whole editor.
    private func smartRun(_ runner: QueryRunner) {
        if let selection = selectedText(runner.sql) {
            runner.run(selection)
        } else if let statement = currentStatement(runner.sql) {
            runner.run(statement)
        } else {
            runner.run()
        }
    }

    private func runSelection(_ runner: QueryRunner) {
        runner.run(selectedText(runner.sql))
    }

    private func runCurrent(_ runner: QueryRunner) {
        runner.run(currentStatement(runner.sql))
    }

    /// The currently selected text, or nil when the selection is empty/blank.
    private func selectedText(_ sql: String) -> String? {
        guard cursor.selectionLength > 0 else { return nil }
        let ns = sql as NSString
        let location = min(cursor.location, ns.length)
        let length = min(cursor.selectionLength, ns.length - location)
        guard length > 0 else { return nil }
        return trimmedOrNil(ns.substring(with: NSRange(location: location, length: length)))
    }

    /// The statement straddling the caret, found by walking `;` boundaries while
    /// honouring strings, quoted identifiers, and comments (mirrors
    /// `SQLStatementSplitter`, but in UTF-16 to match the caret offset). Returns
    /// nil when the caret sits in blank space between statements.
    private func currentStatement(_ sql: String) -> String? {
        let ns = sql as NSString
        let n = ns.length
        guard n > 0 else { return nil }
        let caret = min(cursor.location, n)

        let singleQuote: unichar = 39, doubleQuote: unichar = 34, backtick: unichar = 96
        let dash: unichar = 45, slash: unichar = 47, star: unichar = 42
        let newline: unichar = 10, semicolon: unichar = 59

        var i = 0
        var segmentStart = 0
        while i < n {
            let c = ns.character(at: i)
            switch c {
            case singleQuote, doubleQuote, backtick:
                let quote = c
                i += 1
                while i < n {
                    if ns.character(at: i) == quote {
                        if i + 1 < n, ns.character(at: i + 1) == quote { i += 2; continue }
                        i += 1
                        break
                    }
                    i += 1
                }
            case dash where i + 1 < n && ns.character(at: i + 1) == dash:
                i += 2
                while i < n, ns.character(at: i) != newline { i += 1 }
            case slash where i + 1 < n && ns.character(at: i + 1) == star:
                i += 2
                while i + 1 < n, !(ns.character(at: i) == star && ns.character(at: i + 1) == slash) { i += 1 }
                i += 2
            case semicolon:
                if caret <= i {
                    return trimmedOrNil(ns.substring(with: NSRange(location: segmentStart, length: i - segmentStart)))
                }
                segmentStart = i + 1
                i += 1
            default:
                i += 1
            }
        }
        return trimmedOrNil(ns.substring(with: NSRange(location: segmentStart, length: n - segmentStart)))
    }

    private func trimmedOrNil(_ string: String) -> String? {
        string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
    }

    private func runExplain(runner: QueryRunner) {
        let statements = SQLStatementSplitter.split(runner.sql)
        guard let first = statements.first else { return }
        explainSQL = first
        explainResult = nil
        explainError = nil
        explainLoading = true
        showExplain = true
        Task {
            do {
                explainResult = try await manager.explain(first, on: connectionID, database: runner.database)
                explainError = nil
            } catch {
                explainResult = nil
                explainError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            }
            explainLoading = false
        }
    }
}
