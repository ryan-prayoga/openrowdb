// GlassIconButton.swift
import SwiftUI

/// Uniform 16×16 glass icon button used across toolbars (query editor, table
/// viewer). Keeps `.glass` padding consistent for every icon-only control.
struct GlassIconButton: View {
  let systemName: String
  var help: String = ""
  var accessibility: String = ""
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: systemName).frame(width: 16, height: 16)
    }
    .buttonStyle(.glass)
    .help(help)
    .accessibilityLabel(accessibility.isEmpty ? systemName : accessibility)
  }
}