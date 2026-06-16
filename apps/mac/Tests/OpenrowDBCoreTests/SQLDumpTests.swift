// SQLDumpTests.swift
import XCTest
@testable import OpenrowDBCore

final class SQLDumpTests: XCTestCase {
    private let table = TableRef(schema: "public", name: "Movie")

    private func sampleDump() -> SQLDumpBuilder.TableDump {
        let columns = [
            ColumnDefinition(name: "id", type: "integer", isNullable: false, isPrimaryKey: true),
            ColumnDefinition(name: "title", type: "text", isNullable: true)
        ]
        let data = QueryResult(
            columns: ["id", "title"],
            rows: [["1", "Up"], ["2", nil], ["3", "O'Brien"]]
        )
        return SQLDumpBuilder.TableDump(table: table, columns: columns, data: data)
    }

    func testDumpEmitsDropCreateAndInserts() {
        let sql = SQLDumpBuilder.build([sampleDump()], dialect: .postgres)
        XCTAssertTrue(sql.contains("DROP TABLE IF EXISTS \"public\".\"Movie\";"))
        XCTAssertTrue(sql.contains("CREATE TABLE \"public\".\"Movie\" (\"id\" integer NOT NULL, \"title\" text, PRIMARY KEY (\"id\"));"))
        XCTAssertTrue(sql.contains("INSERT INTO \"public\".\"Movie\" (\"id\", \"title\") VALUES ('1', 'Up');"))
    }

    func testDumpRendersNullAndEscapesQuotes() {
        let sql = SQLDumpBuilder.build([sampleDump()], dialect: .postgres)
        XCTAssertTrue(sql.contains("VALUES ('2', NULL);"))
        XCTAssertTrue(sql.contains("VALUES ('3', 'O''Brien');"))
    }

    func testDumpDropDisabled() {
        let sql = SQLDumpBuilder.build([sampleDump()], dialect: .postgres,
                                       options: .init(dropIfExists: false))
        XCTAssertFalse(sql.contains("DROP TABLE"))
        XCTAssertTrue(sql.contains("CREATE TABLE"))
    }

    func testDumpSchemaOnlyOmitsInserts() {
        let sql = SQLDumpBuilder.build([sampleDump()], dialect: .mysql,
                                       options: .init(includeData: false))
        XCTAssertTrue(sql.contains("CREATE TABLE `public`.`Movie`"))
        XCTAssertFalse(sql.contains("INSERT INTO"))
    }

    func testDumpDataOnlyOmitsSchema() {
        let sql = SQLDumpBuilder.build([sampleDump()], dialect: .postgres,
                                       options: .init(dropIfExists: false, createTable: false))
        XCTAssertFalse(sql.contains("CREATE TABLE"))
        XCTAssertFalse(sql.contains("DROP TABLE"))
        XCTAssertTrue(sql.contains("INSERT INTO \"public\".\"Movie\""))
    }

    func testEmptyTableEmitsSchemaButNoInserts() {
        let empty = SQLDumpBuilder.TableDump(
            table: table,
            columns: [ColumnDefinition(name: "id", type: "integer")],
            data: QueryResult(columns: [], rows: [])
        )
        let sql = SQLDumpBuilder.build([empty], dialect: .postgres)
        XCTAssertTrue(sql.contains("CREATE TABLE"))
        XCTAssertFalse(sql.contains("INSERT INTO"))
    }

    func testFullColumnsSQLPostgresUsesFormatType() {
        let sql = SQLDialect.postgres.fullColumnsSQL(table)
        XCTAssertTrue(sql.contains("format_type(a.atttypid, a.atttypmod)"))
        XCTAssertTrue(sql.contains("'\"public\".\"Movie\"'::regclass"))
        XCTAssertTrue(sql.contains("attnotnull"))
    }

    func testFullColumnsSQLMySQLUsesColumnType() {
        let sql = SQLDialect.mysql.fullColumnsSQL(TableRef(schema: "shop", name: "orders"))
        XCTAssertTrue(sql.contains("column_type"))
        XCTAssertTrue(sql.contains("is_nullable"))
        XCTAssertTrue(sql.contains("table_schema = 'shop'"))
    }
}
