// RenameTableSheet.swift
import OpenrowDBCore
import SwiftUI

/// Modern sheet for renaming a sidebar table (replaces the legacy alert + TextField).
struct RenameTableSheet: View {
  let table: TableRef
  @Binding var name: String
  let onRename: () -> Void
  let onCancel: () -> Void

  private var trimmed: String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canRename: Bool {
    !trimmed.isEmpty && trimmed != table.name
  }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 14) {
        Text("Rename Table")
          .font(.title3.weight(.semibold))
        Text("Enter a new name for \(table.schema).\(table.name).")
          .font(.callout)
          .foregroundStyle(.secondary)
        TextField("New name", text: $name)
          .textFieldStyle(.roundedBorder)
          .onSubmit { if canRename { onRename() } }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)

      Divider()
      HStack {
        Button("Cancel", role: .cancel) { onCancel() }
          .keyboardShortcut(.cancelAction)
          .buttonStyle(.glass)
        Spacer()
        Button("Rename") { onRename() }
          .keyboardShortcut(.defaultAction)
          .buttonStyle(.glassProminent)
          .disabled(!canRename)
      }
      .padding()
    }
    .frame(width: 400)
  }
}