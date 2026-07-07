// QueryTabTitleSuggester.swift
import Foundation

/// Derives a short query-tab title from SQL text (e.g. `SELECT * FROM users` → `users`).
public enum QueryTabTitleSuggester {
  public static func suggest(from sql: String, dialect: SQLDialect = .postgres) -> String? {
    let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let table = tableAfterFrom(in: trimmed, dialect: dialect) {
      return truncate(table)
    }
    return nil
  }

  private static func tableAfterFrom(in sql: String, dialect: SQLDialect) -> String? {
    let upper = sql.uppercased()
    guard let fromRange = upper.range(of: "FROM") else { return nil }
    var index = sql.distance(from: sql.startIndex, to: fromRange.upperBound)
    let chars = Array(sql)
    guard index < chars.count else { return nil }

    skipWhitespace(chars: chars, index: &index)
    guard index < chars.count else { return nil }

    if chars[index] == "(" { return nil }

    if chars[index] == "\"" || chars[index] == "`" {
      let quote = chars[index]
      index += 1
      var name = ""
      while index < chars.count, chars[index] != quote {
        name.append(chars[index])
        index += 1
      }
      return name.isEmpty ? nil : name
    }

    var name = ""
    while index < chars.count {
      let ch = chars[index]
      if ch.isLetter || ch.isNumber || ch == "_" || ch == "$" {
        name.append(ch)
        index += 1
      } else {
        break
      }
    }
    guard !name.isEmpty else { return nil }
    let keywords = Set(dialect.keywords.map { $0.uppercased() })
    if keywords.contains(name.uppercased()) { return nil }
    return name
  }

  private static func skipWhitespace(chars: [Character], index: inout Int) {
    while index < chars.count, chars[index].isWhitespace {
      index += 1
    }
  }

  private static func truncate(_ name: String, maxLength: Int = 24) -> String {
    if name.count <= maxLength { return name }
    let end = name.index(name.startIndex, offsetBy: maxLength)
    return String(name[..<end]) + "…"
  }
}