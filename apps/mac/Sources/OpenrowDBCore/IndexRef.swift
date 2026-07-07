// IndexRef.swift
import Foundation

/// A secondary (non-primary) index on a table.
public struct IndexRef: Sendable, Equatable, Identifiable {
  public let name: String
  public let columns: [String]
  public let isUnique: Bool

  public var id: String { name }

  public init(name: String, columns: [String], isUnique: Bool) {
    self.name = name
    self.columns = columns
    self.isUnique = isUnique
  }
}