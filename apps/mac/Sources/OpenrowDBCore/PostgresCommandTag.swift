// PostgresCommandTag.swift
import Foundation

/// Parses Postgres `CommandComplete` tags into an affected-row count.
/// Mirrors PostgresNIO's `PostgresQueryMetadata` parsing for unit-test coverage.
public enum PostgresCommandTag {
  public static func rowsAffected(in tag: String) -> Int? {
    let parts = tag.split(separator: " ")
    switch parts.first {
    case "INSERT":
      guard parts.count == 3 else { return nil }
      return Int(parts[2])
    case "SELECT" where parts.count == 1:
      return nil
    case "SELECT", "DELETE", "UPDATE", "MOVE", "FETCH", "COPY":
      guard parts.count == 2 else { return nil }
      return Int(parts[1])
    default:
      return nil
    }
  }
}