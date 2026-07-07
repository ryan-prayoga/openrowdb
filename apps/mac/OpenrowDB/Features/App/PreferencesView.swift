// PreferencesView.swift
import SwiftUI

/// App-wide settings surfaced via Settings… (⌘,) and the Settings scene.
struct PreferencesView: View {
  @Environment(AppPreferences.self) private var preferences

  var body: some View {
    @Bindable var preferences = preferences

    Form {
      Section("Table Viewer") {
        Picker("Default page size", selection: $preferences.defaultTablePageSize) {
          ForEach(AppPreferences.tablePageSizeOptions, id: \.self) { size in
            Text("\(size) rows").tag(size)
          }
        }
        .help("Applied when you open a new table tab.")
      }

      Section("Query Editor") {
        HStack {
          Text("Font size")
          Slider(value: $preferences.editorFontSize, in: AppPreferences.editorFontSizeRange, step: 1)
          Text("\(Int(preferences.editorFontSize)) pt")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
        }
        Toggle("Confirm before loading history", isOn: $preferences.confirmHistoryLoad)
          .help("Shows a confirmation when history would replace SQL already in the editor.")
      }

      Section("Query History") {
        Picker("Entries per connection", selection: $preferences.historyDisplayLimit) {
          ForEach(AppPreferences.historyLimitOptions, id: \.self) { limit in
            Text("\(limit)").tag(limit)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 420)
    .padding(20)
  }
}

#Preview {
  PreferencesView()
    .environment(AppPreferences.shared)
}