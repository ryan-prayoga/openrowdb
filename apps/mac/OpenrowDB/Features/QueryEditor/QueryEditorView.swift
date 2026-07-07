// QueryEditorView.swift
import AppKit
import OpenrowDBCore
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var editorAccess = EditorAccess()
    @State private var databases: [String] = []
    @FocusState private var editorFocused: Bool

    @State private var editorHeight: CGFloat = 240
    @State private var dragStartHeight: CGFloat?
    @State private var showRunMenu = false
    @State private var showDatabaseMenu = false
    @State private var showMoreMenu = false
    @State private var databasesLoading = false
    @State private var databasesError: String?

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
                errorPosition: editorErrorPosition(in: runner.outcomes),
                jumpRequest: jumpRequest,
                onCursorChange: { cursor = $0 },
                access: editorAccess
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
        .background(editorShortcutCatchers(runner: runner))
    }

    /// Hidden buttons so ⌘F / ⌘⇧F fire via the responder chain even while the
    /// hosted NSTextView has focus (same pattern as WorkspaceView's ⌘T/⌘W).
    private func editorShortcutCatchers(runner: QueryRunner) -> some View {
        let blank = isBlank(runner.sql)
        return ZStack {
            Button("") {
                editorAccess.presentFindInterface()
                editorFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)

            Button("") {
                runner.sql = SQLFormatter.format(runner.sql, dialect: dialect)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            .disabled(blank)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .accessibilityHidden(true)
    }

    private var dialect: SQLDialect {
        manager.connections.first(where: { $0.id == connectionID })?.driver.dialect ?? .postgres
    }

    private func toolbar(runner: QueryRunner) -> some View {
        let running = isRunning(runner.state)
        let blank = isBlank(runner.sql)
        return HStack(spacing: 8) {
            // Split control: primary press runs (smartRun); the chevron opens a
            // custom glass dropdown. We build this by hand instead of `Menu …
            // primaryAction:` because SwiftUI's `Menu` always renders a native
            // gray NSMenu, which clashes with the dark glass toolbar. A popover
            // lets the dropdown adopt the same Liquid Glass surface as the rest
            // of the chrome.
            GlassEffectContainer(spacing: 2) {
                HStack(spacing: 2) {
                    Button {
                        smartRun(runner)
                    } label: {
                        Label {
                            Text(running ? "Running…" : "Run")
                        } icon: {
                            Image(systemName: running ? "hourglass" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .buttonStyle(.glassProminent)

                    Button {
                        showRunMenu.toggle()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 14, height: 16)
                    }
                    .buttonStyle(.glassProminent)
                    .accessibilityLabel("Run options")
                    .popover(isPresented: $showRunMenu, arrowEdge: .bottom) {
                        runMenu(runner: runner)
                    }
                }
            }
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

            databaseMenu(runner: runner)

            Spacer()

            moreMenu(runner: runner, running: running, blank: blank)

            // History stays in the core set; restyled from `.toggleStyle(.button)`
            // to a `.glass` button (active = accent tint) so it matches the Run
            // and Database controls instead of standing out as a plain toggle.
            Button {
                showHistory.toggle()
            } label: {
                Image(systemName: "clock.arrow.circlepath").frame(width: 16, height: 16)
            }
            .buttonStyle(.glass)
            .foregroundStyle(showHistory ? Color.accentColor : .primary)
            .help("Show query history")
            .accessibilityLabel("History")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .animation(.easeInOut(duration: 0.18), value: running)
    }

    /// Overflow menu for secondary editor tools (format, explain, export,
    /// snippets). Kept off the primary toolbar so Run · Database · History stay
    /// visible; glass popover matches the Run and Database pickers.
    private func moreMenu(runner: QueryRunner, running: Bool, blank: Bool) -> some View {
        let hasExport = runner.outcomes.compactMap(\.result).contains { !$0.columns.isEmpty }
        return Button {
            showMoreMenu.toggle()
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 16, height: 16)
        }
        .buttonStyle(.glass)
        .help("More editor actions")
        .accessibilityLabel("More")
        .popover(isPresented: $showMoreMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 1) {
                RunMenuRow(
                    title: "Format SQL",
                    icon: "text.alignleft",
                    shortcut: "⌘⇧F",
                    disabled: blank
                ) {
                    showMoreMenu = false
                    runner.sql = SQLFormatter.format(runner.sql, dialect: dialect)
                }
                RunMenuRow(
                    title: "Explain Plan",
                    icon: "list.bullet.rectangle",
                    disabled: running || blank
                ) {
                    showMoreMenu = false
                    runExplain(runner: runner)
                }
                Divider().padding(.vertical, 3)
                RunMenuRow(
                    title: showSnippets ? "Hide Snippets" : "Show Snippets",
                    icon: "bookmark",
                    disabled: false
                ) {
                    showMoreMenu = false
                    showSnippets.toggle()
                    if showSnippets { showHistory = false }
                }
                Divider().padding(.vertical, 3)
                RunMenuRow(
                    title: "Export as CSV…",
                    icon: "square.and.arrow.up",
                    disabled: !hasExport
                ) {
                    showMoreMenu = false
                    exportFirstResult(runner: runner, format: .csv)
                }
                RunMenuRow(
                    title: "Export as JSON…",
                    icon: "curlybraces",
                    disabled: !hasExport
                ) {
                    showMoreMenu = false
                    exportFirstResult(runner: runner, format: .json)
                }
                RunMenuRow(
                    title: "Copy as CSV",
                    icon: "doc.on.clipboard",
                    disabled: !hasExport
                ) {
                    showMoreMenu = false
                    copyFirstResult(runner: runner, format: .csv)
                }
                RunMenuRow(
                    title: "Copy as JSON",
                    icon: "doc.on.clipboard",
                    disabled: !hasExport
                ) {
                    showMoreMenu = false
                    copyFirstResult(runner: runner, format: .json)
                }
            }
            .padding(6)
            .frame(width: 248)
        }
    }

    private enum ExportFormat { case csv, json }

    private func firstExportableResult(in runner: QueryRunner) -> QueryResult? {
        runner.outcomes.compactMap(\.result).first { !$0.columns.isEmpty }
    }

    private func exportFirstResult(runner: QueryRunner, format: ExportFormat) {
        guard let result = firstExportableResult(in: runner) else { return }
        switch format {
        case .csv:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.commaSeparatedText]
            panel.nameFieldStringValue = "results.csv"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try Data(ResultExporter.exportCSV(result).utf8).write(to: url, options: .atomic)
            } catch { /* best-effort */ }
        case .json:
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "results.json"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                let data = try ResultExporter.exportJSON(result)
                try data.write(to: url, options: .atomic)
            } catch { /* best-effort */ }
        }
    }

    private func copyFirstResult(runner: QueryRunner, format: ExportFormat) {
        guard let result = firstExportableResult(in: runner) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch format {
        case .csv:
            pasteboard.setString(ResultExporter.exportCSV(result), forType: .string)
        case .json:
            guard let data = try? ResultExporter.exportJSON(result) else { return }
            pasteboard.setString(String(decoding: data, as: UTF8.self), forType: .string)
        }
    }

    /// Glass dropdown for the Run split button. Mirrors the three actions a
    /// native menu would offer, but rendered on the same Liquid Glass surface
    /// as the toolbar so the control reads as one designed unit.
    private func runMenu(runner: QueryRunner) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            RunMenuRow(
                title: "Run Current Statement",
                icon: "play.fill",
                shortcut: "⌘↩"
            ) {
                showRunMenu = false
                runCurrent(runner)
            }
            RunMenuRow(
                title: "Run Selection",
                icon: "text.cursor",
                disabled: editorAccess.selectionLength() == 0
            ) {
                showRunMenu = false
                runSelection(runner)
            }
            Divider().padding(.vertical, 3)
            RunMenuRow(
                title: "Run All Statements",
                icon: "forward.fill",
                shortcut: "⇧⌘↩"
            ) {
                showRunMenu = false
                runner.run()
            }
        }
        .padding(6)
        .frame(width: 248)
    }

    /// One row of `runMenu`. `.plain` button with a tint-filled hover highlight,
    /// matching how AppKit menu items light up on pointer hover.
    private struct RunMenuRow: View {
        let title: String
        var icon: String? = nil
        var shortcut: String? = nil
        var disabled: Bool = false
        let action: () -> Void

        @State private var hovering = false

        private var active: Bool { hovering && !disabled }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    // Reserve the leading slot even when there's no icon so
                    // labels line up (e.g. the database picker only marks the
                    // current row with a checkmark).
                    Group {
                        if let icon { Image(systemName: icon) }
                    }
                    .frame(width: 16)
                    Text(title).lineLimit(1)
                    Spacer(minLength: 16)
                    if let shortcut {
                        Text(shortcut)
                            .foregroundStyle(active ? .white.opacity(0.8) : Color.secondary)
                    }
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background {
                    if active {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor)
                    }
                }
                .contentShape(.rect(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            .onHover { hovering = $0 }
        }
    }

    /// Database this query tab targets. Defaults to the connection's database;
    /// the picker lets the user point a tab at any database on the server so
    /// autocomplete and runs match what they're browsing in the sidebar tree.
    private func databaseMenu(runner: QueryRunner) -> some View {
        let current = currentDatabase(runner)
        return Button {
            showDatabaseMenu.toggle()
            // Reload on open. The onAppear fetch can race ahead of the
            // connection finishing its (re)connect — and after a relaunch the
            // connection may be fully down — so we (re)connect if needed and
            // refetch every time the menu opens.
            if showDatabaseMenu { Task { await loadDatabases() } }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cylinder.split.1x2").frame(width: 16, height: 16)
                Text(current).lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.glass)
        .fixedSize()
        .help("Database for this query tab")
        .accessibilityLabel("Database: \(current)")
        .popover(isPresented: $showDatabaseMenu, arrowEdge: .bottom) {
            databasePopover(runner: runner, current: current)
        }
    }

    /// Glass dropdown for the database picker — same Liquid Glass popover as the
    /// Run menu rather than a native NSMenu, with a checkmark on the active db.
    private func databasePopover(runner: QueryRunner, current: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                if !databases.isEmpty {
                    ForEach(databases, id: \.self) { db in
                        RunMenuRow(
                            title: db,
                            icon: db == current ? "checkmark" : nil
                        ) {
                            showDatabaseMenu = false
                            runner.useDatabase(db)
                        }
                    }
                } else if databasesLoading {
                    statusRow {
                        ProgressView().controlSize(.small)
                        Text("Loading databases…").foregroundStyle(.secondary)
                    }
                } else if let databasesError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(databasesError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .lineLimit(3)
                        Button("Retry") { Task { await loadDatabases() } }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                    }
                    .font(.callout)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                } else {
                    statusRow {
                        Text("No databases").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
        .frame(width: 240)
        .frame(maxHeight: 360)
    }

    private func statusRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .font(.callout)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    /// (Re)connect if needed, then load the database list for the picker.
    /// Surfaces failures instead of silently leaving the menu spinning — the
    /// connection is often simply down (e.g. after a dev relaunch).
    @MainActor
    private func loadDatabases() async {
        if databasesLoading { return }
        databasesLoading = true
        databasesError = nil
        defer { databasesLoading = false }

        if manager.status[connectionID] != ConnectionManager.Status.connected {
            await manager.connect(connectionID)
        }
        do {
            databases = try await manager.databases(on: connectionID)
            if databases.isEmpty { databasesError = nil }
        } catch {
            databasesError = (error as? DatabaseError)?.userMessage ?? error.localizedDescription
        }
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

    private func editorErrorPosition(in outcomes: [QueryRunner.StatementOutcome]) -> Int? {
        outcomes.first(where: { $0.editorErrorPosition != nil })?.editorErrorPosition
    }

    // MARK: - Run targeting

    /// The editor's live text + selection at click time. Reading the NSTextView
    /// directly (via `editorAccess`) rather than the `cursor` snapshot is what
    /// makes partial runs target what's truly selected: the snapshot lags a
    /// render and is stale once the Run menu grabs first responder. Falls back
    /// to the runner's SQL with the caret at the start before the editor exists.
    private func runTarget(_ runner: QueryRunner) -> (text: String, caret: Int, selectionLength: Int) {
        guard let snap = editorAccess.snapshot() else {
            return (runner.sql, 0, 0)
        }
        return (snap.text, snap.selectedRange.location, snap.selectedRange.length)
    }

    /// ⌘↩ behaviour: run the selection if there is one, else the statement under
    /// the caret, else fall back to the whole editor.
    private func smartRun(_ runner: QueryRunner) {
        let target = runTarget(runner)
        if let selection = selectedText(in: target.text, location: target.caret, length: target.selectionLength) {
            runner.run(selection)
        } else if let statement = currentStatement(in: target.text, caret: target.caret) {
            runner.run(statement)
        } else {
            runner.run()
        }
    }

    private func runSelection(_ runner: QueryRunner) {
        let target = runTarget(runner)
        runner.run(selectedText(in: target.text, location: target.caret, length: target.selectionLength))
    }

    private func runCurrent(_ runner: QueryRunner) {
        let target = runTarget(runner)
        runner.run(currentStatement(in: target.text, caret: target.caret))
    }

    /// The selected text, or nil when the selection is empty/blank.
    private func selectedText(in sql: String, location: Int, length: Int) -> String? {
        guard length > 0 else { return nil }
        let ns = sql as NSString
        let start = min(location, ns.length)
        let clampedLength = min(length, ns.length - start)
        guard clampedLength > 0 else { return nil }
        return trimmedOrNil(ns.substring(with: NSRange(location: start, length: clampedLength)))
    }

    /// The statement straddling the caret, found by walking `;` boundaries while
    /// honouring strings, quoted identifiers, and comments (mirrors
    /// `SQLStatementSplitter`, but in UTF-16 to match the caret offset). Returns
    /// nil when the caret sits in blank space between statements.
    private func currentStatement(in sql: String, caret rawCaret: Int) -> String? {
        let ns = sql as NSString
        let n = ns.length
        guard n > 0 else { return nil }
        let caret = min(rawCaret, n)

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
