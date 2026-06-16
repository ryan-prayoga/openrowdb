// SQLWriteDetector.swift
import Foundation

/// Heuristic check for statements that mutate schema or data. Used to block
/// writes on read-only connections before they hit the server.
public enum SQLWriteDetector {
    private static let writePrefixes = [
        "INSERT", "UPDATE", "DELETE", "CREATE", "DROP", "ALTER",
        "TRUNCATE", "GRANT", "REVOKE", "REPLACE", "MERGE", "CALL",
    ]

    public static func containsWrite(_ script: String) -> Bool {
        SQLStatementSplitter.split(script).contains { isWriteStatement($0) }
    }

    public static func isWriteStatement(_ sql: String) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let upper = trimmed.uppercased()
        if upper.hasPrefix("EXPLAIN") || upper.hasPrefix("SHOW") || upper.hasPrefix("DESCRIBE") {
            return false
        }
        if upper.hasPrefix("--") || upper.hasPrefix("/*") { return false }

        let padded = " \(upper) "
        for prefix in writePrefixes {
            if padded.contains(" \(prefix) ") || upper.hasPrefix("\(prefix) ") {
                return true
            }
        }
        return false
    }
}