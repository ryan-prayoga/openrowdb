// ForeignKeyRef.swift
import Foundation

/// An outgoing foreign-key constraint from one column to another table.
public struct ForeignKeyRef: Sendable, Equatable, Identifiable {
    public let column: String
    public let referencedTable: TableRef
    public let referencedColumn: String

    public var id: String { "\(column)->\(referencedTable.id).\(referencedColumn)" }

    public init(column: String, referencedTable: TableRef, referencedColumn: String) {
        self.column = column
        self.referencedTable = referencedTable
        self.referencedColumn = referencedColumn
    }
}