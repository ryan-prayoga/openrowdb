// ReadOnlyBadge.swift
import SwiftUI

/// Connection-level read-only indicator. Shown once in the workspace toolbar
/// rather than duplicated in every tab's action bar.
struct ReadOnlyBadge: View {
  var body: some View {
    Label("Read-only", systemImage: "lock.fill")
      .font(.caption)
      .foregroundStyle(.orange)
      .help("This connection is read-only — writes and DDL are blocked.")
  }
}