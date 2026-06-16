// QueryEditorView.swift
import OpenrowDBCore
import SwiftUI

/// One query tab: SQL editor on top, results (per statement) on the bottom,
/// with a status line and a collapsible history inspector trailing. Keyboard:
/// ⌘Return runs, ⌘. cancels an in-flight run.
struct QueryEditorView: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(QueryHistoryStore.self) private var history
    let connectionID: UUID
    let tabID: UUID

    @State private var runner: QueryRunner?
    @State private var showHistory = false
    @FocusState private var editorFocused: Bool

    var body: some View {
        Group {
            if let runner {
                content(runner: runner)
            } else {
                ProgressView()
            }
        }
        .task(id: tabID) {
            if runner == nil || runner?.tabID != tabID {
                runner = QueryRunner(
                    connectionID: connectionID,
                    tabID: tabID,
                    manager: manager,
                    history: history
                )
            }
        }
    }

    @ViewBuilder
    private func content(runner: QueryRunner) -> some View {
        @Bindable var runner = runner

        HSplitView {
            VSplitView {
                editor(runner: runner)
                    .frame(minHeight: 120, idealHeight: 220)

                QueryResultsView(outcomes: runner.outcomes, state: runner.state)
                    .frame(minHeight: 160, maxHeight: .infinity)
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)

            if showHistory {
                QueryHistoryView(connectionID: connectionID) { sql in
                    runner.sql = sql
                    editorFocused = true
                }
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 380)
            }
        }
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
                onSubmit: { runner.run() }
            )
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
                Label("Run", systemImage: "play.fill")
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
            }

            Spacer()

            ExportButton(outcomes: runner.outcomes)

            Toggle(isOn: $showHistory) {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .toggleStyle(.button)
            .help("Show query history")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
}
