// TabularPasteParser.swift
import Foundation

/// One parsed row as explicit column assignments (avoids `Dictionary` nil-removal).
public struct TabularPasteRow: Sendable {
  public let assignments: [(column: String, value: SQLValue)]

  public init(assignments: [(column: String, value: SQLValue)]) {
    self.assignments = assignments
  }
}

/// Outcome of parsing clipboard TSV/CSV for bulk insert.
public struct TabularPasteParseResult: Sendable {
  public let rows: [TabularPasteRow]
  /// Destination columns that received at least one value.
  public let mappedColumns: [String]
  /// Header cells that did not match any table column.
  public let unmappedHeaders: [String]
  public let warnings: [String]

  public init(
    rows: [TabularPasteRow],
    mappedColumns: [String],
    unmappedHeaders: [String],
    warnings: [String]
  ) {
    self.rows = rows
    self.mappedColumns = mappedColumns
    self.unmappedHeaders = unmappedHeaders
    self.warnings = warnings
  }
}

/// Parses spreadsheet clipboard text (TSV or CSV) into rows mapped to table columns.
public enum TabularPasteParser: Sendable {
  public static func parse(_ text: String, tableColumns: [String]) -> TabularPasteParseResult {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return TabularPasteParseResult(rows: [], mappedColumns: [], unmappedHeaders: [], warnings: ["Clipboard is empty."])
    }

    let delimiter = detectDelimiter(in: trimmed)
    let records = parseRecords(trimmed, delimiter: delimiter)
    guard !records.isEmpty else {
      return TabularPasteParseResult(rows: [], mappedColumns: [], unmappedHeaders: [], warnings: ["No rows found."])
    }

    let columnIndex = Dictionary(uniqueKeysWithValues: tableColumns.enumerated().map { ($0.element.lowercased(), $0.offset) })
    let headerMapping = headerMapping(for: records[0], tableColumns: tableColumns, columnIndex: columnIndex)
    let dataRecords: [[String]]
    let unmappedHeaders: [String]

    if let headerMapping {
      dataRecords = Array(records.dropFirst())
      unmappedHeaders = headerMapping.unmapped
    } else {
      dataRecords = records
      unmappedHeaders = []
    }

    var warnings: [String] = []
    if dataRecords.isEmpty {
      warnings.append("No data rows after the header.")
    }

    var mappedSet = Set<String>()
    var parsedRows: [TabularPasteRow] = []

    for (rowIndex, record) in dataRecords.enumerated() {
      if record.allSatisfy({ $0.isEmpty }) { continue }
      var assignments: [(column: String, value: SQLValue)] = []

      if let headerMapping {
        for (sourceIndex, columnName) in headerMapping.mapped {
          let raw = sourceIndex < record.count ? record[sourceIndex] : ""
          assignments.append((columnName, parseCell(raw)))
          mappedSet.insert(columnName)
        }
      } else {
        for (index, columnName) in tableColumns.enumerated() {
          let raw = index < record.count ? record[index] : ""
          assignments.append((columnName, parseCell(raw)))
          mappedSet.insert(columnName)
        }
        if record.count > tableColumns.count {
          warnings.append("Row \(rowIndex + 1) has extra columns that were ignored.")
        }
      }

      if !assignments.isEmpty {
        parsedRows.append(TabularPasteRow(assignments: assignments))
      }
    }

    let mappedColumns = tableColumns.filter { mappedSet.contains($0) }
    if parsedRows.isEmpty, warnings.isEmpty {
      warnings.append("No insertable rows found.")
    }

    return TabularPasteParseResult(
      rows: parsedRows,
      mappedColumns: mappedColumns,
      unmappedHeaders: unmappedHeaders,
      warnings: warnings
    )
  }

  // MARK: - Delimiter

  private static func detectDelimiter(in text: String) -> Character {
    guard let firstLine = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).first else {
      return "\t"
    }
    let line = String(firstLine)
    let tabs = line.filter { $0 == "\t" }.count
    let commas = line.filter { $0 == "," }.count
    return tabs >= commas && tabs > 0 ? "\t" : ","
  }

  // MARK: - Header mapping

  private struct HeaderMapping {
    let mapped: [(Int, String)]
    let unmapped: [String]
  }

  private static func headerMapping(
    for record: [String],
    tableColumns: [String],
    columnIndex: [String: Int]
  ) -> HeaderMapping? {
    var mapped: [(Int, String)] = []
    var unmapped: [String] = []
    var matched = 0

    for (index, header) in record.enumerated() {
      let key = header.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if let colIndex = columnIndex[key] {
        mapped.append((index, tableColumns[colIndex]))
        matched += 1
      } else if !key.isEmpty {
        unmapped.append(header)
      }
    }

    guard matched > 0 else { return nil }
    return HeaderMapping(mapped: mapped, unmapped: unmapped)
  }

  // MARK: - Record parsing

  private static func parseRecords(_ text: String, delimiter: Character) -> [[String]] {
    var records: [[String]] = []
    var currentRecord: [String] = []
    var currentField = ""
    var inQuotes = false
    var index = text.startIndex

    func endField() {
      currentRecord.append(currentField)
      currentField = ""
    }

    func endRecord() {
      endField()
      if !currentRecord.isEmpty || !records.isEmpty {
        records.append(currentRecord)
      }
      currentRecord = []
    }

    while index < text.endIndex {
      let char = text[index]

      if inQuotes {
        if char == "\"" {
          let next = text.index(after: index)
          if next < text.endIndex, text[next] == "\"" {
            currentField.append("\"")
            index = next
          } else {
            inQuotes = false
          }
        } else {
          currentField.append(char)
        }
      } else if char == "\"" {
        inQuotes = true
      } else if char == delimiter {
        endField()
      } else if char == "\n" {
        endRecord()
      } else if char == "\r" {
        let next = text.index(after: index)
        if next < text.endIndex, text[next] == "\n" {
          index = next
        }
        endRecord()
      } else {
        currentField.append(char)
      }

      index = text.index(after: index)
    }

    if !currentField.isEmpty || !currentRecord.isEmpty {
      endRecord()
    } else if text.last == delimiter {
      // Trailing delimiter with no newline — flush the final empty field.
      endRecord()
    }

    return records
  }

  private static func parseCell(_ raw: String) -> SQLValue {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return .null }
    let lower = trimmed.lowercased()
    if lower == "null" || lower == "\\n" { return .null }
    return .text(trimmed)
  }
}