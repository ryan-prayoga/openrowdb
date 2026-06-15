// EmptyStateView.swift
import SwiftUI

struct EmptyStateView: View {
    @Binding var showingNewConnection: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "cylinder.split.1x2")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No connection selected")
                .font(.title2)
            Text("Pick a connection from the sidebar, or create a new one with ⌘N.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingNewConnection = true
            } label: {
                Label("New Connection", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
