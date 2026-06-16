// ResultExporterTests.swift
import XCTest
@testable import OpenrowDBCore

final class ResultExporterTests: XCTestCase {

    // MARK: - CSV

    func testCSVEmptyResult() {
        XCTAssertEqual(ResultExporter.exportCSV(.empty), "")
    }

    func testCSVHeaderOnly() {
        let result = QueryResult(columns: ["a", "b"], rows: [])
        XCTAssertEqual(ResultExporter.exportCSV(result), "a,b\r\n")
    }

    func testCSVPlainCells() {
        let result = QueryResult(
            columns: ["id", "name"],
            rows: [["1", "Alice"], ["2", "Bob"]]
        )
        XCTAssertEqual(
            ResultExporter.exportCSV(result),
            "id,name\r\n1,Alice\r\n2,Bob\r\n"
        )
    }

    func testCSVNullCellsAreEmpty() {
        let result = QueryResult(
            columns: ["a", "b", "c"],
            rows: [["x", nil, "z"], [nil, nil, nil]]
        )
        XCTAssertEqual(
            ResultExporter.exportCSV(result),
            "a,b,c\r\nx,,z\r\n,,\r\n"
        )
    }

    func testCSVQuotesFieldsWithCommas() {
        let result = QueryResult(columns: ["x"], rows: [["a,b,c"]])
        XCTAssertEqual(ResultExporter.exportCSV(result), "x\r\n\"a,b,c\"\r\n")
    }

    func testCSVQuotesFieldsWithNewlines() {
        let result = QueryResult(columns: ["x"], rows: [["line1\nline2"]])
        XCTAssertEqual(ResultExporter.exportCSV(result), "x\r\n\"line1\nline2\"\r\n")
    }

    func testCSVEscapesEmbeddedDoubleQuotes() {
        let result = QueryResult(columns: ["x"], rows: [["she said \"hi\""]])
        XCTAssertEqual(
            ResultExporter.exportCSV(result),
            "x\r\n\"she said \"\"hi\"\"\"\r\n"
        )
    }

    func testCSVDistinguishesNullFromEmptyString() {
        // RFC 4180 has no NULL sentinel; we render SQL NULL as a bare empty
        // field and an empty string as a quoted empty field to preserve the
        // distinction on round-trip with strict parsers.
        let result = QueryResult(columns: ["a", "b"], rows: [[nil, ""]])
        XCTAssertEqual(ResultExporter.exportCSV(result), "a,b\r\n,\r\n")
    }

    func testCSVUnicodePreserved() {
        let result = QueryResult(columns: ["name"], rows: [["日本語"], ["café"]])
        XCTAssertEqual(
            ResultExporter.exportCSV(result),
            "name\r\n日本語\r\ncafé\r\n"
        )
    }

    // MARK: - JSON

    func testJSONEmptyResult() throws {
        let data = try ResultExporter.exportJSON(.empty)
        XCTAssertEqual(String(data: data, encoding: .utf8), "[\n]")
    }

    func testJSONPlainCells() throws {
        let result = QueryResult(
            columns: ["id", "name"],
            rows: [["1", "Alice"], ["2", "Bob"]]
        )
        let json = try String(data: ResultExporter.exportJSON(result), encoding: .utf8)
        XCTAssertEqual(
            json,
            "[\n  {\"id\": \"1\", \"name\": \"Alice\"},\n  {\"id\": \"2\", \"name\": \"Bob\"}\n]"
        )
    }

    func testJSONNullCellsBecomeJSONNull() throws {
        let result = QueryResult(
            columns: ["a", "b"],
            rows: [["x", nil]]
        )
        let json = try String(data: ResultExporter.exportJSON(result), encoding: .utf8)
        XCTAssertEqual(json, "[\n  {\"a\": \"x\", \"b\": null}\n]")
    }

    func testJSONEscapesControlCharactersAndQuotes() throws {
        let result = QueryResult(
            columns: ["x"],
            rows: [["tab\there\nand \"quote\" \\backslash"]]
        )
        let json = try String(data: ResultExporter.exportJSON(result), encoding: .utf8)
        XCTAssertEqual(
            json,
            "[\n  {\"x\": \"tab\\there\\nand \\\"quote\\\" \\\\backslash\"}\n]"
        )
    }

    func testJSONPreservesColumnOrder() throws {
        let result = QueryResult(
            columns: ["z", "a", "m"],
            rows: [["1", "2", "3"]]
        )
        let json = try String(data: ResultExporter.exportJSON(result), encoding: .utf8)
        XCTAssertEqual(
            json,
            "[\n  {\"z\": \"1\", \"a\": \"2\", \"m\": \"3\"}\n]"
        )
    }

    func testJSONIsParseableByJSONSerialization() throws {
        let result = QueryResult(
            columns: ["id", "name", "note"],
            rows: [
                ["1", "Alice", nil],
                ["2", "Bob", "has\nnewline"]
            ]
        )
        let data = try ResultExporter.exportJSON(result)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?[0]["id"] as? String, "1")
        XCTAssertEqual(parsed?[0]["name"] as? String, "Alice")
        XCTAssertTrue(parsed?[0]["note"] is NSNull)
        XCTAssertEqual(parsed?[1]["note"] as? String, "has\nnewline")
    }
}
