// ExplainPlanView.swift
import OpenrowDBCore
import SwiftUI

/// Sheet showing EXPLAIN output for one SQL statement.
struct ExplainPlanView: View {
    @Environment(\.dismiss) private var dismiss
    let sql: String
    let result: QueryResult?
    let error: String?
    let loading: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 480)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Explain Plan", systemImage: "list.bullet.rectangle")
                .font(.headline)
            Spacer()
            if loading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            PlaceholderView(
                title: "Explain failed",
                subtitle: error,
                systemImage: "exclamationmark.triangle",
                variant: .error
            )
        } else if let result, !result.columns.isEmpty {
            ExplainPlanGrid(result: result)
        } else if loading {
            ProgressView("Running EXPLAIN…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PlaceholderView(
                title: "No plan",
                subtitle: "EXPLAIN returned no rows.",
                systemImage: "list.bullet.rectangle"
            )
        }
    }

    private var footer: some View {
        HStack {
            Text(sql.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct ExplainPlanGrid: View {
    let result: QueryResult
    @State private var sortOrder: [ColumnComparator] = []
    @State private var selection: Set<Int> = []

    var body: some View {
        ResultsGrid(
            result: result,
            sortOrder: $sortOrder,
            selection: $selection
        )
    }
}