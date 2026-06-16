// QueryResultsView.swift
import OpenrowDBCore
import SwiftUI

/// Renders the per-statement outcomes of a query run. Single-statement runs
/// fill the pane with a `ResultsGrid`; multi-statement runs use a TabView so
/// users can flip between each statement's result without losing context.
struct QueryResultsView: View {
    let outcomes: [QueryRunner.StatementOutcome]
    let state: QueryRunner.State

    @State private var selection: Int = 0

    var body: some View {
        if outcomes.isEmpty {
            placeholder
        } else if outcomes.count == 1 {
            outcomePane(outcomes[0])
        } else {
            TabView(selection: $selection) {
                ForEach(Array(outcomes.enumerated()), id: \.offset) { index, outcome in
                    outcomePane(outcome)
                        .tag(index)
                        .tabItem { Text(label(for: outcome, index: index)) }
                }
            }
        }
    }

    @ViewBuilder
    private func outcomePane(_ outcome: QueryRunner.StatementOutcome) -> some View {
        if let error = outcome.error {
            errorPane(sql: outcome.sql, message: error, durationMs: outcome.durationMs)
        } else if let result = outcome.result {
            resultPane(sql: outcome.sql, result: result, durationMs: outcome.durationMs)
        } else {
            placeholder
        }
    }

    private func resultPane(sql: String, result: QueryResult, durationMs: Int) -> some View {
        // Local sort state per pane is intentionally a no-op binding — server-side
        // sorting for ad-hoc query results is out of scope for v1.
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(metaLine(result: result, durationMs: durationMs))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            Divider()
            ResultsGrid(
                result: result,
                sortOrder: .constant([]),
                selection: .constant(nil)
            )
        }
    }

    private func errorPane(sql: String, message: String, durationMs: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Query failed", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.headline)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Divider()
            Text(sql)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            Text("Failed in \(durationMs) ms")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placeholder: some View {
        ContentUnavailableView(
            isRunning ? "Running…" : "No results yet",
            systemImage: isRunning ? "hourglass" : "tablecells",
            description: Text(isRunning ? "" : "Press ⌘Return to run the query.")
        )
    }

    private var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private func metaLine(result: QueryResult, durationMs: Int) -> String {
        if let rowsAffected = result.rowsAffected, result.columns.isEmpty {
            return "\(rowsAffected) row\(rowsAffected == 1 ? "" : "s") affected · \(durationMs) ms"
        }
        return "\(result.rows.count) row\(result.rows.count == 1 ? "" : "s") · \(result.columns.count) col\(result.columns.count == 1 ? "" : "s") · \(durationMs) ms"
    }

    private func label(for outcome: QueryRunner.StatementOutcome, index: Int) -> String {
        let prefix = "#\(index + 1)"
        if let error = outcome.error {
            _ = error
            return "\(prefix) ⚠︎"
        }
        if let result = outcome.result {
            if let rowsAffected = result.rowsAffected, result.columns.isEmpty {
                return "\(prefix) (\(rowsAffected))"
            }
            return "\(prefix) (\(result.rows.count))"
        }
        return prefix
    }
}
