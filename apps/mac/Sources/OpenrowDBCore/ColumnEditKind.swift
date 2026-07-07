// ColumnEditKind.swift
import Foundation

/// UI editing strategy inferred from a column's SQL type string.
public enum ColumnEditKind: Sendable, Equatable {
  case text
  case boolean
  case date
  case dateTime
  case json
}

/// Maps driver-reported SQL types to an inline-edit control kind.
public enum ColumnEditKindResolver: Sendable {
  public static func kind(for sqlType: String) -> ColumnEditKind {
    let normalized = sqlType.lowercased()
    if normalized.contains("json") { return .json }
    if isBoolean(normalized) { return .boolean }
    if isDateOnly(normalized) { return .date }
    if isDateTime(normalized) { return .dateTime }
    return .text
  }

  private static func isBoolean(_ type: String) -> Bool {
    type == "bool" || type == "boolean" || type.hasPrefix("tinyint(1)")
  }

  private static func isDateOnly(_ type: String) -> Bool {
    type == "date"
  }

  private static func isDateTime(_ type: String) -> Bool {
    type.contains("timestamp") || type.contains("datetime") || type == "time"
  }
}