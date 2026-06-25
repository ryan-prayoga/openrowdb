// QueryGettingStartedView.swift
import SwiftUI

/// Shown in the results pane of a brand-new, never-run query tab instead of an
/// empty void. Surfaces the editor's key shortcuts so the blank canvas teaches
/// rather than just sits there. Purely informational — no actions wired in.
struct QueryGettingStartedView: View {
    @State private var appeared = false

    private let hints: [Hint] = [
        Hint(keys: ["⌘", "↩"], label: "Run query"),
        Hint(keys: ["⌘", "⇧", "F"], label: "Format SQL"),
        Hint(keys: ["⇥"], label: "Autocomplete"),
        Hint(keys: ["⌘", "."], label: "Cancel run"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 5) {
                Text("Write your query")
                    .font(.system(.title3, design: .default, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Type SQL in the editor above, then run it.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            GlassEffectContainer {
                HStack(spacing: 8) {
                    ForEach(hints) { hint in
                        hintChip(hint)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .onAppear {
            withAnimation(.easeOut(duration: 0.24)) { appeared = true }
        }
    }

    private func hintChip(_ hint: Hint) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(Array(hint.keys.enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .frame(minWidth: 16)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: .rect(cornerRadius: 5, style: .continuous))
                }
            }
            Text(hint.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(in: .rect(cornerRadius: 9, style: .continuous))
    }

    private struct Hint: Identifiable {
        let id = UUID()
        let keys: [String]
        let label: String
    }
}

#Preview {
    QueryGettingStartedView()
        .frame(width: 700, height: 320)
}
