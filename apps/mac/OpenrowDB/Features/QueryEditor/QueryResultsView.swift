// QueryResultsView.swift
import OpenrowDBCore
import SwiftUI

/// Renders the per-statement outcomes of a query run. Single-statement runs
/// fill the pane with a `ResultsGrid`; multi-statement runs use a TabView so
/// users can flip between each statement's result without losing context.
struct QueryResultsView: View {
    let outcomes: [QueryRunner.StatementOutcome]
    let state: QueryRunner.State
    var leadingInset: CGFloat = 0
    var onJumpToError: ((Int) -> Void)? = nil

    @State private var selection: Int = 0

    var body: some View {
        if outcomes.isEmpty {
            if isFreshTab {
                Color.clear
            } else {
                placeholder
            }
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

    private var isFreshTab: Bool {
        if case .idle = state, outcomes.isEmpty { return true }
        return false
    }

    @ViewBuilder
    private func outcomePane(_ outcome: QueryRunner.StatementOutcome) -> some View {
        if let error = outcome.error {
            errorPane(
                sql: outcome.sql,
                message: error,
                durationMs: outcome.durationMs,
                position: outcome.errorPosition
            )
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
                selection: .constant(nil),
                leadingInset: leadingInset
            )
        }
    }

    private func errorPane(sql: String, message: String, durationMs: Int, position: Int?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Query failed", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .font(.headline)
                if let position, let onJumpToError {
                    Spacer()
                    Button {
                        onJumpToError(position)
                    } label: {
                        Label("Jump to error", systemImage: "arrow.right.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Divider()
            Text(annotatedSQL(sql, position: position))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            Text("Failed in \(durationMs) ms")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            if let position, let onJumpToError {
                onJumpToError(position)
            }
        }
    }

    /// Render the SQL with the offending character highlighted in red. The
    /// `position` is 1-indexed (Postgres convention); convert and clamp to
    /// avoid building an invalid AttributedString range when the server's
    /// position is past the SQL length (rare, but observed for trailing
    /// whitespace errors).
    private func annotatedSQL(_ sql: String, position: Int?) -> AttributedString {
        var attributed = AttributedString(sql)
        guard let position, position > 0 else { return attributed }
        let zero = position - 1
        let chars = Array(sql)
        guard zero < chars.count else { return attributed }
        var start = zero
        var end = zero
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        if isIdent(chars[zero]) {
            while start > 0, isIdent(chars[start - 1]) { start -= 1 }
            while end < chars.count, isIdent(chars[end]) { end += 1 }
        } else {
            end = zero + 1
        }
        let prefix = String(chars[0..<start])
        let token = String(chars[start..<end])
        guard let prefixIdx = attributed.range(of: prefix),
              let tokenIdx = attributed[prefixIdx.upperBound...].range(of: token) else {
            return attributed
        }
        attributed[tokenIdx].foregroundColor = .red
        attributed[tokenIdx].underlineStyle = .single
        return attributed
    }

    private var placeholder: some View {
        PlaceholderView(
            title: isRunning ? "Running…" : "No results yet",
            subtitle: isRunning ? nil : "Press ⌘Return to run the query.",
            systemImage: isRunning ? "hourglass" : "tablecells"
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
