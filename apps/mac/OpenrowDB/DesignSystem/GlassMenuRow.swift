// GlassMenuRow.swift
import SwiftUI

/// One row inside a glass popover menu — shared by query editor, transfer, and
/// database pickers. Plain button with accent-filled hover highlight.
struct GlassMenuRow: View {
  let title: String
  var icon: String? = nil
  var shortcut: String? = nil
  var disabled: Bool = false
  let action: () -> Void

  @State private var hovering = false

  private var active: Bool { hovering && !disabled }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Group {
          if let icon { Image(systemName: icon) }
        }
        .frame(width: DesignTokens.toolbarIconSize)
        Text(title).lineLimit(1)
        Spacer(minLength: 16)
        if let shortcut {
          Text(shortcut)
            .foregroundStyle(active ? .white.opacity(0.8) : Color.secondary)
        }
      }
      .font(.callout)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: .leading)
      .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .background {
        if active {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.accentColor)
        }
      }
      .contentShape(.rect(cornerRadius: 6))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.4 : 1)
    .onHover { hovering = $0 }
  }
}