// StructureDDLPreview.swift
import Foundation

/// Builds the DDL statements that would run when saving a structure tab.
public enum StructureDDLPreview {
  public enum Mode: Sendable, Equatable {
    case create
    case edit
  }

  public static func statements(
    mode: Mode,
    dialect: SQLDialect,
    database: String,
    schema: String,
    tableName: String,
    originalName: String,
    existingTable: TableRef?,
    columns: [ColumnDefinition],
    originalColumns: [ColumnDefinition]
  ) -> [String] {
    let trimmed = tableName.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return [] }

    switch mode {
    case .create:
      let table = TableRef(database: database, schema: schema, name: trimmed)
      let cleaned = clean(columns)
      guard !cleaned.isEmpty else { return [] }
      return [dialect.createTableSQL(table, columns: cleaned)]

    case .edit:
      guard let table = existingTable else { return [] }
      let edited = clean(columns)
      var sql: [String] = []

      for original in originalColumns where !edited.contains(where: { $0.id == original.id }) {
        sql.append(dialect.dropColumnSQL(table, column: original.name))
      }
      for column in edited where !originalColumns.contains(where: { $0.id == column.id }) {
        sql.append(dialect.addColumnSQL(table, column: column))
      }
      for column in edited {
        if let original = originalColumns.first(where: { $0.id == column.id }),
           original.name != column.name {
          sql.append(dialect.renameColumnSQL(table, column: original.name, to: column.name))
        }
      }
      if trimmed != originalName {
        sql.append(dialect.renameTableSQL(table, to: trimmed))
      }
      return sql
    }
  }

  private static func clean(_ columns: [ColumnDefinition]) -> [ColumnDefinition] {
    columns
      .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
      .map { col in
        var copy = col
        copy.name = col.name.trimmingCharacters(in: .whitespaces)
        copy.type = col.type.trimmingCharacters(in: .whitespaces)
        return copy
      }
  }
}