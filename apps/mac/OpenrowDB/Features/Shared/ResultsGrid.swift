// ResultsGrid.swift
import OpenrowDBCore
import SwiftUI

/// A reusable result-set grid: a SwiftUI `Table` with columns derived dynamically
/// from a `QueryResult`, clickable header sorting, row selection, and a companion
/// row inspector. Shared by the schema browser (Phase 2) and the query editor
/// (Phase 3) so result rendering lives in exactly one place.
struct ResultsGrid: View {
    let result: QueryResult
    @Binding var sortOrder: [ColumnComparator]
    @Binding var selection: Int?

    private var columns: [ResultColumn] {
        result.columns.enumerated().map { ResultColumn(id: $0.offset, name: $0.element) }
    }

    private var rows: [ResultRow] {
        result.rows.enumerated().map { ResultRow(id: $0.offset, cells: $0.element) }
    }

    var body: some View {
        if columns.isEmpty {
            ContentUnavailableView("No columns", systemImage: "tablecells")
        } else {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumnForEach(columns) { column in
                    TableColumn(
                        column.name,
                        sortUsing: ColumnComparator(columnIndex: column.id, columnName: column.name, order: .forward)
                    ) { row in
                        CellText(value: row.cells.indices.contains(column.id) ? row.cells[column.id] : nil)
                    }
                }
            }
        }
    }
}

/// Trailing inspector listing every column/value of the selected row, with the
/// column's SQL type when available. Values are copyable and not truncated.
struct RowInspector: View {
    let result: QueryResult
    let selectedRowID: Int?
    /// Column name -> SQL type, when introspection is available.
    var columnTypes: [String: String] = [:]

    private var row: [String?]? {
        guard let selectedRowID, result.rows.indices.contains(selectedRowID) else { return nil }
        return result.rows[selectedRowID]
    }

    var body: some View {
        Group {
            if let row {
                List {
                    ForEach(Array(result.columns.enumerated()), id: \.offset) { index, name in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                                if let type = columnTypes[name] {
                                    Text(type)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: .rect(cornerRadius: 4))
                                }
                            }
                            CellText(value: row.indices.contains(index) ? row[index] : nil)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else {
                ContentUnavailableView("No row selected", systemImage: "rectangle.and.text.magnifyingglass")
            }
        }
    }
}

/// Renders a cell value, distinguishing SQL NULL from text. Copyable.
struct CellText: View {
    let value: String?

    var body: some View {
        if let value {
            Text(value).monospaced().textSelection(.enabled)
        } else {
            Text("NULL").foregroundStyle(.secondary).italic()
        }
    }
}

// MARK: - Backing models

struct ResultColumn: Identifiable {
    let id: Int
    let name: String
}

struct ResultRow: Identifiable {
    let id: Int
    let cells: [String?]
}

/// Sort descriptor carried by clickable table headers. Sorting is performed
/// server-side (ORDER BY), so the client-side `compare` is a no-op — the column
/// header still shows the sort indicator from `order`.
struct ColumnComparator: SortComparator {
    let columnIndex: Int
    let columnName: String
    var order: SortOrder

    func compare(_ lhs: ResultRow, _ rhs: ResultRow) -> ComparisonResult {
        .orderedSame
    }
}
