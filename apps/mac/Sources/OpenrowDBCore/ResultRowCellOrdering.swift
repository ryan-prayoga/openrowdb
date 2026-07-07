// ResultRowCellOrdering.swift
import Foundation

/// Client-side ordering for grid cells (query results, EXPLAIN plans).
public enum ResultRowCellOrdering {
  public static func compare(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
    switch (lhs, rhs) {
    case (nil, nil):
      return .orderedSame
    case (nil, _):
      return .orderedDescending
    case (_, nil):
      return .orderedAscending
    case let (left?, right?):
      if let leftNum = parseNumber(left), let rightNum = parseNumber(right) {
        if leftNum == rightNum { return .orderedSame }
        return leftNum < rightNum ? .orderedAscending : .orderedDescending
      }
      let text = left.localizedStandardCompare(right)
      switch text {
      case .orderedAscending: return .orderedAscending
      case .orderedDescending: return .orderedDescending
      case .orderedSame: return .orderedSame
      }
    }
  }

  private static func parseNumber(_ text: String) -> Decimal? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
  }
}