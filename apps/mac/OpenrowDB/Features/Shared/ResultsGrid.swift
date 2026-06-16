// ResultsGrid.swift
import OpenrowDBCore
import SwiftUI

// Shared mutable state for inline row editing. Owned by TableDataView,
// read by ResultsGrid cells — @Observable means any cell that reads a
// property re-renders automatically when that property changes.
@Observable
final class InlineEditState {
    var rowID: Int? = nil
    var values: [String: String?] = [:]
    var predicates: [(column: String, value: SQLValue)] = []
}

/// A reusable result-set grid: a SwiftUI `Table` with columns derived dynamically
/// from a `QueryResult`, clickable header sorting, row selection, and a companion
/// row inspector. Shared by the schema browser (Phase 2) and the query editor
/// (Phase 3) so result rendering lives in exactly one place.
struct ResultsGrid: View {
    let result: QueryResult
    @Binding var sortOrder: [ColumnComparator]
    @Binding var selection: Int?
    /// Leading inset for the scroll content, in points. Used when the grid fills
    /// a workspace tab beside the translucent NavigationSplitView sidebar, which
    /// overlays the detail's leading edge; the hosted NSTableView otherwise
    /// scrolls its columns under the sidebar. Defaults to 0 (e.g. the Browse
    /// split, where the grid never abuts the sidebar).
    var leadingInset: CGFloat = 0

    // Row action callbacks — nil = action not available in this context
    var canMutate: Bool = false
    /// Non-nil while a row is being inline-edited; cells for that row render
    /// as TextFields bound to editState.values.
    var inlineEdit: InlineEditState? = nil
    var onCommitEdit: (() -> Void)? = nil
    var onCancelEdit: (() -> Void)? = nil
    var onDoubleClick: ((Int) -> Void)? = nil
    var onEdit: ((Int) -> Void)? = nil
    var onDelete: ((Int) -> Void)? = nil
    var onDuplicate: ((Int) -> Void)? = nil

    private var columns: [ResultColumn] {
        result.columns.enumerated().map { ResultColumn(id: $0.offset, name: $0.element) }
    }

    private var rows: [ResultRow] {
        result.rows.enumerated().map { ResultRow(id: $0.offset, cells: $0.element) }
    }

    var body: some View {
        if columns.isEmpty {
            PlaceholderView(
                title: "No columns",
                subtitle: "This result set has no columns to display.",
                systemImage: "tablecells"
            )
        } else {
            Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumnForEach(columns) { column in
                    TableColumn(
                        column.name,
                        sortUsing: ColumnComparator(columnIndex: column.id, columnName: column.name, order: .forward)
                    ) { row in
                        if let edit = inlineEdit, row.id == edit.rowID {
                            InlineCellTextField(
                                column: column.name,
                                editState: edit,
                                onCommit: onCommitEdit,
                                onCancel: onCancelEdit
                            )
                        } else {
                            CellText(value: row.cells.indices.contains(column.id) ? row.cells[column.id] : nil)
                        }
                    }
                }
            }
            .contextMenu(forSelectionType: Int.self) { items in
                if let id = items.first {
                    if canMutate {
                        Button { onEdit?(id) } label: {
                            Label("Edit Row", systemImage: "pencil")
                        }
                        Button { onDuplicate?(id) } label: {
                            Label("Duplicate Row", systemImage: "plus.square.on.square")
                        }
                        Divider()
                        Button(role: .destructive) { onDelete?(id) } label: {
                            Label("Delete Row", systemImage: "trash")
                        }
                        Divider()
                    }
                    Button { copyRow(id) } label: {
                        Label("Copy as TSV", systemImage: "doc.on.clipboard")
                    }
                }
            } primaryAction: { items in
                // Double-click
                if let id = items.first { onDoubleClick?(id) }
            }
            // Leading padding equal to the sidebar overlap. The hosted
            // NSTableView extends its scroll area into the leading safe area
            // (under the translucent sidebar); padding by that amount pulls the
            // columns back out so the first column isn't hidden by the sidebar.
            .padding(.leading, leadingInset)
        }
    }

    private func copyRow(_ id: Int) {
        guard result.rows.indices.contains(id) else { return }
        let row = result.rows[id]
        let text = zip(result.columns, row).map { "\($0)\t\($1 ?? "NULL")" }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// TextField rendered inside a cell while its row is being inline-edited.
private struct InlineCellTextField: View {
    let column: String
    let editState: InlineEditState
    let onCommit: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        TextField(
            "NULL",
            text: Binding(
                get: { editState.values[column].flatMap { $0 } ?? "" },
                set: { editState.values[column] = .some($0) }
            )
        )
        .font(.system(.body, design: .monospaced))
        .textFieldStyle(.plain)
        .onSubmit { onCommit?() }
        .onKeyPress(.escape) {
            onCancel?()
            return .handled
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
                PlaceholderView(
                    title: "No row selected",
                    subtitle: "Click a row in the table to inspect its values.",
                    systemImage: "rectangle.and.text.magnifyingglass"
                )
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
