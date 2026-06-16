// ResultExporter.swift
import Foundation

/// Pure, stateless converters from a `QueryResult` to CSV / JSON payloads.
///
/// CSV output follows RFC 4180:
/// - Fields are separated by `,`
/// - Records are terminated by CRLF (`\r\n`)
/// - A field containing `"`, `,`, CR, or LF is wrapped in double quotes;
///   inner double quotes are escaped by doubling (`"` → `""`)
/// - SQL NULL is rendered as an empty (unquoted) field
///
/// JSON output is an array of objects keyed by column name. SQL NULL becomes
/// JSON `null`. All cell values are emitted as strings (no type inference) to
/// match the driver-agnostic `QueryResult` contract.
public enum ResultExporter: Sendable {

    // MARK: - CSV

    public static func exportCSV(_ result: QueryResult) -> String {
        guard !result.columns.isEmpty || !result.rows.isEmpty else { return "" }

        var output = ""
        output.append(joinCSVRow(result.columns))
        output.append("\r\n")

        for row in result.rows {
            output.append(joinCSVRow(row.map { $0 ?? "" }, nullMask: row.map { $0 == nil }))
            output.append("\r\n")
        }
        return output
    }

    // MARK: - JSON

    public static func exportJSON(_ result: QueryResult) throws -> Data {
        // We hand-roll JSON encoding instead of going through JSONSerialization
        // because we need to preserve column order across all platforms (NSDictionary
        // randomizes keys) and emit `null` for SQL NULL without using NSNull.
        var output = "[\n"
        for (rowIndex, row) in result.rows.enumerated() {
            output.append("  {")
            for (colIndex, column) in result.columns.enumerated() {
                if colIndex > 0 { output.append(", ") }
                output.append(jsonQuote(column))
                output.append(": ")
                let cell: String?? = colIndex < row.count ? row[colIndex] : nil
                if case let .some(value?) = cell {
                    output.append(jsonQuote(value))
                } else {
                    output.append("null")
                }
            }
            output.append(rowIndex == result.rows.count - 1 ? "}\n" : "},\n")
        }
        output.append("]")

        guard let data = output.data(using: .utf8) else {
            throw ExportError.encodingFailed
        }
        return data
    }

    // MARK: - Helpers

    /// Join one CSV record. `nullMask`, when supplied, marks fields that should
    /// be emitted bare (empty, no quotes) regardless of their string value.
    private static func joinCSVRow(_ fields: [String], nullMask: [Bool]? = nil) -> String {
        var parts: [String] = []
        parts.reserveCapacity(fields.count)
        for (index, field) in fields.enumerated() {
            if nullMask?[index] == true {
                parts.append("")
            } else {
                parts.append(escapeCSVField(field))
            }
        }
        return parts.joined(separator: ",")
    }

    private static func escapeCSVField(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        if !needsQuoting { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private static func jsonQuote(_ string: String) -> String {
        var output = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": output.append("\\\"")
            case "\\": output.append("\\\\")
            case "\n": output.append("\\n")
            case "\r": output.append("\\r")
            case "\t": output.append("\\t")
            case "\u{08}": output.append("\\b")
            case "\u{0C}": output.append("\\f")
            default:
                if scalar.value < 0x20 {
                    output.append(String(format: "\\u%04x", scalar.value))
                } else {
                    output.append(Character(scalar))
                }
            }
        }
        output.append("\"")
        return output
    }
}

// MARK: - Errors

public enum ExportError: Error, Sendable {
    case encodingFailed
}
