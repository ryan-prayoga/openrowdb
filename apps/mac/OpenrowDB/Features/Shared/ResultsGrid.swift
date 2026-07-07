// ResultsGrid.swift
import AppKit
import OpenrowDBCore
import SwiftUI

/// Context for generating INSERT/UPDATE SQL from a grid row.
struct RowSQLCopyContext {
    let table: TableRef
    let dialect: SQLDialect
    let primaryKeys: [String]
}

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
    @Binding var selection: Set<Int>
    /// When set, column resize state is restored and saved across sessions.
    var gridID: String? = nil
    /// Width of the translucent NavigationSplitView sidebar that overlaps the
    /// detail's leading edge (the leading safe-area inset), threaded down from
    /// `WorkspaceView`. The hosted NSTableView fills the full window width and
    /// anchors at the window's left edge — under the sidebar — when its columns
    /// are wider than the visible area, hiding the first column. We make it
    /// ignore the leading safe area (so it always starts at the window edge) and
    /// then pad it back out by this amount so the first column lands flush
    /// against the sidebar in every state. 0 when the grid never abuts the
    /// sidebar (e.g. the Browse split).
    var leadingInset: CGFloat = 0
    /// When false, column headers are not sortable (ad-hoc query results have no
    /// server-side re-fetch on sort — disabling avoids a misleading affordance).
    var sortable: Bool = true

    // Row action callbacks — nil = action not available in this context
    var canMutate: Bool = false
    /// Non-nil while a row is being inline-edited; cells for that row render
    /// as TextFields bound to editState.values.
    var inlineEdit: InlineEditState? = nil
    var onCommitEdit: (() -> Void)? = nil
    var onCancelEdit: (() -> Void)? = nil
    var onDoubleClick: ((Int) -> Void)? = nil
    var onEdit: ((Int) -> Void)? = nil
    var onDeleteRows: ((Set<Int>) -> Void)? = nil
    var onDuplicate: ((Int) -> Void)? = nil
    /// When set, context menu offers Copy as INSERT / UPDATE.
    var sqlCopy: RowSQLCopyContext? = nil
    /// Column name → SQL type, for typed inline editors.
    var columnTypes: [String: String] = [:]

    private var columns: [ResultColumn] {
        result.columns.enumerated().map { ResultColumn(id: $0.offset, name: $0.element) }
    }

    private var rows: [ResultRow] {
        result.rows.enumerated().map { ResultRow(id: $0.offset, cells: $0.element) }
    }

    @State private var columnCustomization = TableColumnCustomization<ResultRow>()

    var body: some View {
        if columns.isEmpty {
            PlaceholderView(
                title: "No columns",
                subtitle: "This result set has no columns to display.",
                systemImage: "tablecells"
            )
        } else if sortable {
            gridTable(sortOrder: $sortOrder)
        } else {
            gridTable(sortOrder: nil)
        }
    }

    /// SwiftUI `Table` requires a homogeneous `TableColumn` sort-comparator type
    /// inside `TableColumnForEach` — an `if sortable` branch won't compile. Two
    /// top-level tables instead: one with `sortUsing:`, one without.
    @ViewBuilder
    private func gridTable(sortOrder: Binding<[ColumnComparator]>?) -> some View {
        if let sortOrder {
            gridChrome(
                Table(rows, selection: $selection, sortOrder: sortOrder, columnCustomization: $columnCustomization) {
                    TableColumnForEach(columns) { column in
                        TableColumn(
                            column.name,
                            sortUsing: ColumnComparator(columnIndex: column.id, columnName: column.name, order: .forward)
                        ) { row in
                            gridCell(column: column, row: row)
                        }
                    }
                }
            )
        } else {
            gridChrome(
                Table(rows, selection: $selection, columnCustomization: $columnCustomization) {
                    TableColumnForEach(columns) { column in
                        TableColumn(column.name) { row in
                            gridCell(column: column, row: row)
                        }
                    }
                }
            )
        }
    }

    private var gridAccessibilityLabel: String {
        let rowCount = result.rows.count
        let columnCount = result.columns.count
        let rowWord = rowCount == 1 ? "row" : "rows"
        let colWord = columnCount == 1 ? "column" : "columns"
        return "Query results, \(rowCount) \(rowWord), \(columnCount) \(colWord)"
    }

    @ViewBuilder
    private func gridChrome<Content: View>(_ table: Content) -> some View {
        table
            .accessibilityLabel(gridAccessibilityLabel)
            .accessibilityHint(sortable ? "Click column headers to sort" : "Read-only result set")
            .contextMenu(forSelectionType: Int.self) { items in
                selectionContextMenu(items)
            } primaryAction: { items in
                if let id = items.first { onDoubleClick?(id) }
            }
            .onAppear { restoreColumnCustomization() }
            .onChange(of: columnCustomization) { _, customization in
                persistColumnCustomization(customization)
            }
            .ignoresSafeArea(.container, edges: leadingInset > 0 ? .leading : [])
            .padding(.leading, leadingInset)
    }

    @ViewBuilder
    private func gridCell(column: ResultColumn, row: ResultRow) -> some View {
        if let edit = inlineEdit, row.id == edit.rowID {
            InlineCellTextField(
                column: column.name,
                sqlType: columnTypes[column.name] ?? "",
                editState: edit,
                onCommit: onCommitEdit,
                onCancel: onCancelEdit
            )
        } else {
            CellText(value: row.cells.indices.contains(column.id) ? row.cells[column.id] : nil)
        }
    }

    @ViewBuilder
    private func selectionContextMenu(_ items: Set<Int>) -> some View {
        let targetIDs = contextTargetIDs(items)
        if !targetIDs.isEmpty {
            if targetIDs.count == 1, let id = targetIDs.first {
                if canMutate {
                    Button { onEdit?(id) } label: {
                        Label("Edit Row", systemImage: "pencil")
                    }
                    Button { onDuplicate?(id) } label: {
                        Label("Duplicate Row", systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) { onDeleteRows?(targetIDs) } label: {
                        Label("Delete Row", systemImage: "trash")
                    }
                    Divider()
                }
                Button { copyRows(targetIDs) } label: {
                    Label("Copy as TSV", systemImage: "doc.on.clipboard")
                }
                if let sqlCopy {
                    Button { copyRowAsInsert(id, context: sqlCopy) } label: {
                        Label("Copy as INSERT", systemImage: "text.append")
                    }
                    if !sqlCopy.primaryKeys.isEmpty {
                        Button { copyRowAsUpdate(id, context: sqlCopy) } label: {
                            Label("Copy as UPDATE", systemImage: "text.badge.checkmark")
                        }
                    }
                }
            } else {
                Button { copyRows(targetIDs) } label: {
                    Label("Copy \(targetIDs.count) Rows as TSV", systemImage: "doc.on.clipboard")
                }
                if canMutate, onDeleteRows != nil {
                    Divider()
                    Button(role: .destructive) { onDeleteRows?(targetIDs) } label: {
                        Label("Delete \(targetIDs.count) Rows", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func contextTargetIDs(_ items: Set<Int>) -> Set<Int> {
        if items.isEmpty { return selection }
        if selection.isSuperset(of: items) { return selection }
        return items
    }

    private func restoreColumnCustomization() {
        guard let gridID, let saved = GridColumnCustomizationStore.load(gridID: gridID) else { return }
        columnCustomization = saved
    }

    private func persistColumnCustomization(_ customization: TableColumnCustomization<ResultRow>) {
        guard let gridID else { return }
        GridColumnCustomizationStore.save(gridID: gridID, customization)
    }

    private func copyRows(_ ids: Set<Int>) {
        let sorted = ids.sorted()
        let lines = sorted.compactMap { id -> String? in
            guard result.rows.indices.contains(id) else { return nil }
            return result.rows[id].map { $0 ?? "NULL" }.joined(separator: "\t")
        }
        guard !lines.isEmpty else { return }
        paste(lines.joined(separator: "\n"))
    }

    private func copyRowAsInsert(_ id: Int, context: RowSQLCopyContext) {
        guard let values = rowValues(id) else { return }
        let cols = values.map(\.column)
        let sqlValues = values.map(\.value)
        let sql = context.dialect.insertRowSQL(context.table, columns: cols, values: sqlValues)
        paste(sql)
    }

    private func copyRowAsUpdate(_ id: Int, context: RowSQLCopyContext) {
        guard let values = rowValues(id) else { return }
        let pkSet = Set(context.primaryKeys)
        let assignments = values.filter { !pkSet.contains($0.column) }
        let predicates = values.filter { pkSet.contains($0.column) }
        guard !predicates.isEmpty else { return }
        let sql = context.dialect.updateRowSQL(context.table, assignments: assignments, predicates: predicates)
        paste(sql)
    }

    private func rowValues(_ id: Int) -> [(column: String, value: SQLValue)]? {
        guard result.rows.indices.contains(id) else { return nil }
        let row = result.rows[id]
        return result.columns.enumerated().map { index, name in
            let cell = row.indices.contains(index) ? row[index] : nil
            return (column: name, value: cell.map(SQLValue.text) ?? .null)
        }
    }

    private func paste(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// TextField rendered inside a cell while its row is being inline-edited.
private struct InlineCellTextField: View {
    let column: String
    let sqlType: String
    let editState: InlineEditState
    let onCommit: (() -> Void)?
    let onCancel: (() -> Void)?

    var body: some View {
        TypedCellEditor(
            column: column,
            sqlType: sqlType,
            text: Binding(
                get: { editState.values[column].flatMap { $0 } ?? "" },
                set: { editState.values[column] = .some($0) }
            ),
            onCommit: onCommit,
            onCancel: onCancel
        )
    }
}

/// Trailing inspector listing every column/value of the selected row, with the
/// column's SQL type when available. Values are copyable and not truncated.
struct RowInspector: View {
    let result: QueryResult
    let selectedRowID: Int?
    /// Column name -> SQL type, when introspection is available.
    var columnTypes: [String: String] = [:]
    var foreignKeys: [ForeignKeyRef] = []
    var onFollowFK: ((ForeignKeyRef, String) -> Void)? = nil

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
                            if let value = row.indices.contains(index) ? row[index] : nil,
                               let fk = foreignKeys.first(where: { $0.column == name }),
                               let onFollowFK {
                                Button {
                                    onFollowFK(fk, value)
                                } label: {
                                    Label(
                                        "Follow → \(fk.referencedTable.name).\(fk.referencedColumn)",
                                        systemImage: "arrow.right.circle"
                                    )
                                    .font(.caption)
                                }
                                .buttonStyle(.borderless)
                            }
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
                .accessibilityLabel(value)
        } else {
            Text("NULL").foregroundStyle(.secondary).italic()
                .accessibilityLabel("NULL")
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
