// QueryResult.swift
import Foundation

/// String-rendered result set, ready for a SwiftUI results grid.
///
/// Cells are pre-rendered to `String?` (nil = SQL NULL) so the UI layer stays
/// free of driver-specific decoding. Typed access can come later if needed.
public struct QueryResult: Sendable, Equatable {
    public let columns: [String]
    public let rows: [[String?]]
    /// Rows affected by an INSERT/UPDATE/DELETE, when the driver reports it.
    public let rowsAffected: Int?

    public init(columns: [String], rows: [[String?]], rowsAffected: Int? = nil) {
        self.columns = columns
        self.rows = rows
        self.rowsAffected = rowsAffected
    }

    /// A result carrying no columns/rows — e.g. a DDL or empty command.
    public static let empty = QueryResult(columns: [], rows: [], rowsAffected: nil)
}
