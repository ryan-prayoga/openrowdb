// BulkInsertSheet.swift
import OpenrowDBCore
import SwiftUI

/// Confirms and executes a bulk insert from parsed clipboard rows.
struct BulkInsertSheet: View {
  @Environment(\.dismiss) private var dismiss

  let tableName: String
  let parseResult: TabularPasteParseResult
  let onInsert: () async throws -> Void

  @State private var inserting = false
  @State private var errorMessage: String?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
      Divider()
      footer
    }
    .frame(width: 480, height: 360)
  }

  private var header: some View {
    HStack {
      Label("Paste Rows", systemImage: "doc.on.clipboard")
        .font(.headline)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private var content: some View {
    if parseResult.rows.isEmpty {
      PlaceholderView(
        title: "Nothing to insert",
        subtitle: parseResult.warnings.first ?? "Clipboard has no usable rows.",
        systemImage: "doc.on.clipboard",
        variant: .error
      )
    } else {
      List {
        Section {
          LabeledContent("Table", value: tableName)
          LabeledContent("Rows", value: "\(parseResult.rows.count)")
          LabeledContent("Columns", value: parseResult.mappedColumns.joined(separator: ", "))
        }
        if !parseResult.unmappedHeaders.isEmpty {
          Section("Ignored columns") {
            Text(parseResult.unmappedHeaders.joined(separator: ", "))
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        if !parseResult.warnings.isEmpty {
          Section("Notes") {
            ForEach(parseResult.warnings, id: \.self) { warning in
              Text(warning).font(.callout).foregroundStyle(.secondary)
            }
          }
        }
      }
      .listStyle(.sidebar)
    }
  }

  private var footer: some View {
    HStack {
      if let errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle")
          .font(.callout)
          .foregroundStyle(.red)
          .lineLimit(2)
      }
      Spacer()
      if inserting { ProgressView().controlSize(.small) }
      Button("Cancel") { dismiss() }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.glass)
      Button("Insert \(parseResult.rows.count) Rows") { insert() }
        .buttonStyle(.glassProminent)
        .disabled(parseResult.rows.isEmpty || inserting)
        .keyboardShortcut(.defaultAction)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private func insert() {
    inserting = true
    errorMessage = nil
    Task {
      do {
        try await onInsert()
        dismiss()
      } catch {
        errorMessage = DatabaseErrorPresenter.message(for: error)
      }
      inserting = false
    }
  }
}