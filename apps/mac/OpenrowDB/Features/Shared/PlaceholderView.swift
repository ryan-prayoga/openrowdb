// PlaceholderView.swift
import SwiftUI

/// Premium empty-state placeholder used across the app (table viewer "No
/// rows", browse sidebar "No tables", query results "Run a query to see
/// results"). Replaces SwiftUI's stock `ContentUnavailableView`, which
/// renders too small and too high-contrast for our editorial dark theme.
///
/// Typography is intentionally hierarchical: title is medium weight at body
/// size, subtitle drops to footnote with secondary color. Icon sits at 56pt
/// with `.tertiary` foreground style so it recedes; this matches the
/// design-system guideline "icon supports text, never competes with it".
///
/// Named `PlaceholderView` (not `EmptyStateView`) because the latter is
/// already taken by the connection-picker hero in `App/EmptyStateView.swift`.
struct PlaceholderView: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var variant: Variant = .neutral

    enum Variant {
        case neutral
        case error
    }

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(iconStyle)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(.title3, design: .default, weight: .medium))
                    .foregroundStyle(.secondary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(.callout))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .frame(maxWidth: 380)
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

    private var iconStyle: AnyShapeStyle {
        switch variant {
        case .neutral: return AnyShapeStyle(.tertiary)
        case .error: return AnyShapeStyle(.red.opacity(0.7))
        }
    }
}

#Preview("Neutral") {
    PlaceholderView(
        title: "No rows yet",
        subtitle: "This table is empty. Insert a row or run a query to populate it.",
        systemImage: "tablecells"
    )
    .frame(width: 600, height: 400)
}

#Preview("Error") {
    PlaceholderView(
        title: "Couldn't load tables",
        subtitle: "Connection refused on 127.0.0.1:5432. Check that the server is running.",
        systemImage: "exclamationmark.triangle",
        variant: .error
    )
    .frame(width: 600, height: 400)
}
