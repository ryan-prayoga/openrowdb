// AppPreferences.swift
import Foundation
import Observation

/// UserDefaults-backed app preferences, injected via SwiftUI environment.
@MainActor
@Observable
final class AppPreferences {
  static let shared = AppPreferences()

  /// Rows fetched per page when a table tab first opens.
  var defaultTablePageSize: Int {
    didSet { persist(Keys.defaultTablePageSize, defaultTablePageSize) }
  }

  /// Monospaced point size for the SQL editor.
  var editorFontSize: Double {
    didSet { persist(Keys.editorFontSize, editorFontSize) }
  }

  /// Max history entries shown per connection in the inspector.
  var historyDisplayLimit: Int {
    didSet { persist(Keys.historyDisplayLimit, historyDisplayLimit) }
  }

  /// Ask before replacing non-empty editor SQL when loading from history.
  var confirmHistoryLoad: Bool {
    didSet { persist(Keys.confirmHistoryLoad, confirmHistoryLoad) }
  }

  static let tablePageSizeOptions = [50, 100, 200, 500]
  static let historyLimitOptions = [50, 100, 200, 500]
  static let editorFontSizeRange = 11.0...20.0

  private enum Keys {
    static let defaultTablePageSize = "openrowdb.defaultTablePageSize"
    static let editorFontSize = "openrowdb.editorFontSize"
    static let historyDisplayLimit = "openrowdb.historyDisplayLimit"
    static let confirmHistoryLoad = "openrowdb.confirmHistoryLoad"
  }

  private init() {
    let defaults = UserDefaults.standard
    defaultTablePageSize = Self.clampPageSize(
      defaults.object(forKey: Keys.defaultTablePageSize) as? Int ?? 100
    )
    editorFontSize = Self.clampFontSize(
      defaults.object(forKey: Keys.editorFontSize) as? Double ?? 13
    )
    historyDisplayLimit = Self.clampHistoryLimit(
      defaults.object(forKey: Keys.historyDisplayLimit) as? Int ?? 200
    )
    if defaults.object(forKey: Keys.confirmHistoryLoad) == nil {
      confirmHistoryLoad = true
    } else {
      confirmHistoryLoad = defaults.bool(forKey: Keys.confirmHistoryLoad)
    }
  }

  private func persist(_ key: String, _ value: Int) {
    UserDefaults.standard.set(value, forKey: key)
  }

  private func persist(_ key: String, _ value: Double) {
    UserDefaults.standard.set(value, forKey: key)
  }

  private func persist(_ key: String, _ value: Bool) {
    UserDefaults.standard.set(value, forKey: key)
  }

  private static func clampPageSize(_ value: Int) -> Int {
    tablePageSizeOptions.contains(value) ? value : 100
  }

  private static func clampHistoryLimit(_ value: Int) -> Int {
    historyLimitOptions.contains(value) ? value : 200
  }

  private static func clampFontSize(_ value: Double) -> Double {
    min(max(value, editorFontSizeRange.lowerBound), editorFontSizeRange.upperBound)
  }
}