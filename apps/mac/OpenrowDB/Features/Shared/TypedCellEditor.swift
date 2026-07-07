// TypedCellEditor.swift
import OpenrowDBCore
import SwiftUI

/// Inline cell editor chosen from the column SQL type.
struct TypedCellEditor: View {
  let column: String
  let sqlType: String
  @Binding var text: String
  var onCommit: (() -> Void)?
  var onCancel: (() -> Void)?

  private var kind: ColumnEditKind {
    ColumnEditKindResolver.kind(for: sqlType)
  }

  var body: some View {
    Group {
      switch kind {
      case .boolean:
        booleanEditor
      case .date:
        dateEditor(hasTime: false)
      case .dateTime:
        dateEditor(hasTime: true)
      case .json:
        jsonEditor
      case .text:
        textEditor
      }
    }
    .onKeyPress(.escape) {
      onCancel?()
      return .handled
    }
  }

  private var textEditor: some View {
    TextField("NULL", text: $text)
      .font(.system(.body, design: .monospaced))
      .textFieldStyle(.plain)
      .onSubmit { onCommit?() }
  }

  private var booleanEditor: some View {
    Picker("", selection: $text) {
      Text("true").tag("true")
      Text("false").tag("false")
      Text("NULL").tag("")
    }
    .labelsHidden()
    .pickerStyle(.menu)
  }

  private func dateEditor(hasTime: Bool) -> some View {
    HStack(spacing: 6) {
      DatePicker(
        "",
        selection: Binding(
          get: { parseDate(text, hasTime: hasTime) ?? Date() },
          set: { text = formatDate($0, hasTime: hasTime) }
        ),
        displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date]
      )
      .labelsHidden()
      Button("NULL") { text = "" }
        .font(.caption)
        .buttonStyle(.borderless)
    }
    .onSubmit { onCommit?() }
  }

  private var jsonEditor: some View {
    TextEditor(text: $text)
      .font(.system(.caption, design: .monospaced))
      .frame(minHeight: 48, maxHeight: 80)
      .scrollContentBackground(.hidden)
      .padding(4)
      .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 4))
      .onSubmit { onCommit?() }
  }

  private func parseDate(_ value: String, hasTime: Bool) -> Date? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let formats = hasTime
      ? ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"]
      : ["yyyy-MM-dd"]
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    for format in formats {
      formatter.dateFormat = format
      if let date = formatter.date(from: trimmed) { return date }
    }
    return nil
  }

  private func formatDate(_ date: Date, hasTime: Bool) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = hasTime ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd"
    return formatter.string(from: date)
  }
}