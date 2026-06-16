// OnboardingView.swift
import SwiftUI

/// First-run welcome sheet. Shown once on fresh install; suppressed via
/// UserDefaults `hasSeenOnboarding` so it never reappears unless cleared.
struct OnboardingView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            hero
            Divider()
            featureList
            Divider()
            footer
        }
        .frame(width: 540, height: 520)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 4) {
                Text("Welcome to OpenrowDB")
                    .font(.largeTitle.weight(.semibold))
                Text("A native macOS database client for Postgres and MySQL.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 36)
        .padding(.bottom, 28)
        .padding(.horizontal, 32)
    }

    // MARK: - Feature list

    private struct Feature {
        let icon: String
        let title: String
        let subtitle: String
    }

    private let features: [Feature] = [
        Feature(
            icon: "bolt.horizontal.circle",
            title: "Connect instantly",
            subtitle: "Postgres and MySQL via ⌘N. Credentials stored securely in Keychain."
        ),
        Feature(
            icon: "tablecells",
            title: "Browse and edit rows",
            subtitle: "Insert, update, and delete rows with a primary-key–safe editor."
        ),
        Feature(
            icon: "terminal",
            title: "SQL editor with autocomplete",
            subtitle: "⌘Return runs, Tab autocompletes keywords and schema. Multi-statement and export included."
        ),
        Feature(
            icon: "arrow.up.arrow.down.square",
            title: "Import and export",
            subtitle: "Dump and restore whole databases as .sql files — schema-only or full data."
        ),
    ]

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(features, id: \.title) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 28, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title).font(.callout.weight(.medium))
                        Text(feature.subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Get Started") {
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

#Preview {
    OnboardingView(onDismiss: {})
}
