// ColumnFilterOperator.swift
import Foundation

/// Comparison operator for single-column table filters in the browse grid.
public enum ColumnFilterOperator: String, Sendable, CaseIterable, Codable, Equatable {
  case contains
  case equals
  case notEquals
  case greaterThan
  case lessThan
  case startsWith
  case endsWith

  public var label: String {
    switch self {
    case .contains: "Contains"
    case .equals: "Equals (=)"
    case .notEquals: "Not equals (≠)"
    case .greaterThan: "Greater than (>)"
    case .lessThan: "Less than (<)"
    case .startsWith: "Starts with"
    case .endsWith: "Ends with"
    }
  }
}