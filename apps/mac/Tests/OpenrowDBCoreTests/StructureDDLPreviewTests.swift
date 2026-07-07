// StructureDDLPreviewTests.swift
import XCTest
@testable import OpenrowDBCore

final class StructureDDLPreviewTests: XCTestCase {
  private let table = TableRef(schema: "public", name: "users")

  func testCreateMode() {
    let columns = [
      ColumnDefinition(name: "id", type: "serial", isNullable: false, isPrimaryKey: true),
      ColumnDefinition(name: "email", type: "text", isNullable: false),
    ]
    let sql = StructureDDLPreview.statements(
      mode: .create,
      dialect: .postgres,
      database: "app",
      schema: "public",
      tableName: "users",
      originalName: "",
      existingTable: nil,
      columns: columns,
      originalColumns: []
    )
    XCTAssertEqual(sql.count, 1)
    XCTAssertTrue(sql[0].contains("CREATE TABLE"))
    XCTAssertTrue(sql[0].contains("PRIMARY KEY"))
  }

  func testEditModeRenameAndAddColumn() {
    let original = [
      ColumnDefinition(id: UUID(), name: "id", type: "integer", isNullable: false, isPrimaryKey: true),
    ]
    let edited = original + [ColumnDefinition(name: "email", type: "text")]
    let sql = StructureDDLPreview.statements(
      mode: .edit,
      dialect: .postgres,
      database: "app",
      schema: "public",
      tableName: "accounts",
      originalName: "users",
      existingTable: table,
      columns: edited,
      originalColumns: original
    )
    XCTAssertEqual(sql.count, 2)
    XCTAssertTrue(sql[0].contains("ADD COLUMN"))
    XCTAssertTrue(sql[1].contains("RENAME TO"))
  }
}