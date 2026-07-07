// ShortcutChip.swift
import SwiftUI

/// Renders a keyboard shortcut as rounded key caps — shared by Getting Started
/// hints and the Shortcuts Help sheet.
struct ShortcutChip: View {
  let keys: [String]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(keys, id: \.self) { key in
        Text(key)
          .font(.system(.caption, design: .rounded, weight: .medium))
          .padding(.horizontal, 6)
          .padding(.vertical, 3)
          .background(.quaternary, in: .rect(cornerRadius: 5, style: .continuous))
      }
    }
  }
}