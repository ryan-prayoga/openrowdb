// BrowseView.swift
import OpenrowDBCore
import SwiftUI

/// Schema browser for a connected database: searchable table list (grouped by
/// schema, with row counts) on the left, a sortable paged results grid on the right.
struct BrowseView: View {
    @Environment(ConnectionManager.self) private var manager
    let connectionID: UUID

    private let pageSize = 100

    @State private var tables: [TableRef] = []
    @State private var tableCounts: [TableRef.ID: Int] = [:]
    @State private var tablesError: String?
    @State private var loadingTables = false
    @State private var search = ""

    @State private var selectedTableID: TableRef.ID?
    @State private var result: QueryResult?
    @State private var rowsError: String?
    @State private var loadingRows = false
    @State private var page = 0
    @State private var totalRows: Int?
    @State private var sortOrder: [ColumnComparator] = []

    private var selectedTable: TableRef? {
        tables.first { $0.id == selectedTableID }
    }

    private var filteredTables: [TableRef] {
        guard !search.isEmpty else { return tables }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    /// Distinct schemas present in the (filtered) table list, in first-seen order.
    private var schemas: [String] {
        var seen: [String] = []
        for table in filteredTables where !seen.contains(table.schema) {
            seen.append(table.schema)
        }
        return seen
    }

    private var currentSort: SortSpec? {
        sortOrder.first.map { SortSpec(column: $0.columnName, ascending: $0.order == .forward) }
    }

    var body: some View {
        HSplitView {
            tableListPane
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)

            resultsPane
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: connectionID) { await reload() }
        .onChange(of: selectedTableID) {
            page = 0
            sortOrder = []
            result = nil
            totalRows = nil
            Task {
                await loadCount()
                await loadRows()
            }
        }
        .onChange(of: page) { Task { await loadRows() } }
        .onChange(of: sortOrder) {
            page = 0
            Task { await loadRows() }
        }
    }

    // MARK: - Table list

    private var tableListPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter tables", text: $search)
                    .textFieldStyle(.plain)
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .disabled(loadingTables)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            Divider()
            tableList
        }
    }

    @ViewBuilder
    private var tableList: some View {
        if loadingTables && tables.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let tablesError {
            ContentUnavailableView("Couldn't load tables", systemImage: "exclamationmark.triangle", description: Text(tablesError))
        } else if filteredTables.isEmpty {
            ContentUnavailableView(search.isEmpty ? "No tables" : "No matches", systemImage: "tablecells")
        } else {
            List(selection: $selectedTableID) {
                ForEach(schemas, id: \.self) { schema in
                    Section(schema) {
                        ForEach(filteredTables.filter { $0.schema == schema }) { table in
                            Label(table.name, systemImage: "tablecells")
                                .badge(tableCounts[table.id].map { "\($0)" } ?? nil)
                                .help("\(table.schema).\(table.name)")
                                .tag(table.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsPane: some View {
        if selectedTable == nil {
            ContentUnavailableView("Pick a table", systemImage: "arrow.left", description: Text("Select a table to browse its rows."))
        } else if loadingRows && result == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let rowsError {
            ContentUnavailableView("Query failed", systemImage: "exclamationmark.triangle", description: Text(rowsError))
        } else if totalRows == 0 {
            ContentUnavailableView("No rows", systemImage: "tablecells")
        } else if let result, !result.columns.isEmpty {
            VStack(spacing: 0) {
                ResultsTable(result: result, sortOrder: $sortOrder)
                Divider()
                paginationBar
            }
        } else {
            Color.clear
        }
    }

    private var firstRowIndex: Int { page * pageSize + 1 }
    private var lastRowIndex: Int { page * pageSize + (result?.rows.count ?? 0) }
    private var hasNextPage: Bool {
        guard let totalRows else { return (result?.rows.count ?? 0) == pageSize }
        return (page + 1) * pageSize < totalRows
    }

    private var paginationBar: some View {
        HStack(spacing: 12) {
            Button { page -= 1 } label: { Label("Previous", systemImage: "chevron.left") }
                .disabled(page == 0 || loadingRows)
                .labelStyle(.iconOnly)

            Button { page += 1 } label: { Label("Next", systemImage: "chevron.right") }
                .disabled(!hasNextPage || loadingRows)
                .labelStyle(.iconOnly)

            Text(rangeLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if loadingRows {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var rangeLabel: String {
        if let totalRows {
            return "\(firstRowIndex)–\(lastRowIndex) of \(totalRows)"
        }
        return "\(firstRowIndex)–\(lastRowIndex)"
    }

    // MARK: - Loading

    private func reload() async {
        await loadTables()
        await loadCounts()
        if selectedTable != nil {
            await loadCount()
            await loadRows()
        }
    }

    private func loadTables() async {
        loadingTables = true
        tablesError = nil
        defer { loadingTables = false }
        do {
            tables = try await manager.tables(on: connectionID)
        } catch {
            tablesError = Self.humanize(error)
        }
    }

    /// Load row counts for every table, in the background. Best-effort: a failed
    /// count just leaves that table's badge empty.
    private func loadCounts() async {
        for table in tables {
            if let count = try? await manager.countRows(table, on: connectionID) {
                tableCounts[table.id] = count
            }
        }
    }

    private func loadCount() async {
        guard let selectedTable else { return }
        totalRows = try? await manager.countRows(selectedTable, on: connectionID)
    }

    private func loadRows() async {
        guard let selectedTable else {
            result = nil
            return
        }
        loadingRows = true
        rowsError = nil
        defer { loadingRows = false }
        do {
            result = try await manager.fetchRows(
                selectedTable,
                on: connectionID,
                limit: pageSize,
                offset: page * pageSize,
                sort: currentSort
            )
        } catch {
            rowsError = Self.humanize(error)
            result = nil
        }
    }

    private static func humanize(_ error: Error) -> String {
        (error as? DatabaseError)?.userMessage ?? String(describing: error)
    }
}

// MARK: - Results grid

private struct ResultColumn: Identifiable {
    let id: Int
    let name: String
}

private struct ResultRow: Identifiable {
    let id: Int
    let cells: [String?]
}

/// Sort descriptor carried by clickable table headers. Sorting is performed
/// server-side (ORDER BY), so the client-side `compare` is a no-op — the column
/// header still shows the sort indicator from `order`.
private struct ColumnComparator: SortComparator {
    let columnIndex: Int
    let columnName: String
    var order: SortOrder

    func compare(_ lhs: ResultRow, _ rhs: ResultRow) -> ComparisonResult {
        .orderedSame
    }
}

/// A SwiftUI `Table` with columns derived dynamically from a `QueryResult`,
/// with clickable column-header sorting wired to `sortOrder`.
private struct ResultsTable: View {
    let result: QueryResult
    @Binding var sortOrder: [ColumnComparator]

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
            Table(rows, sortOrder: $sortOrder) {
                TableColumnForEach(columns) { column in
                    TableColumn(
                        column.name,
                        sortUsing: ColumnComparator(columnIndex: column.id, columnName: column.name, order: .forward)
                    ) { row in
                        cell(row.cells.indices.contains(column.id) ? row.cells[column.id] : nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ value: String?) -> some View {
        if let value {
            Text(value).monospaced().textSelection(.enabled)
        } else {
            Text("NULL").foregroundStyle(.secondary).italic()
        }
    }
}
