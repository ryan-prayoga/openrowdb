// ForeignKeyRef.swift
import Foundation

/// An outgoing foreign-key constraint from one column to another table.
public struct ForeignKeyRef: Sendable, Equatable, Identifiable {
    public let constraintName: String
    public let column: String
    public let referencedTable: TableRef
    public let referencedColumn: String

    public var id: String { "\(constraintName):\(column)->\(referencedTable.id).\(referencedColumn)" }

    public init(
        constraintName: String,
        column: String,
        referencedTable: TableRef,
        referencedColumn: String
    ) {
        self.constraintName = constraintName
        self.column = column
        self.referencedTable = referencedTable
        self.referencedColumn = referencedColumn
    }
}