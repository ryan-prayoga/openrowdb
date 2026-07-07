// GridColumnCustomizationStore.swift
import Foundation
import SwiftUI

/// Persists SwiftUI `TableColumnCustomization` per grid identity (table tab, etc.).
enum GridColumnCustomizationStore {
  private static let prefix = "openrowdb.gridColumns."

  static func load(gridID: String) -> TableColumnCustomization<ResultRow>? {
    guard let data = UserDefaults.standard.data(forKey: prefix + gridID) else { return nil }
    return try? JSONDecoder().decode(TableColumnCustomization<ResultRow>.self, from: data)
  }

  static func save(gridID: String, _ customization: TableColumnCustomization<ResultRow>) {
    guard let data = try? JSONEncoder().encode(customization) else { return }
    UserDefaults.standard.set(data, forKey: prefix + gridID)
  }
}