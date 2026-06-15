// BrowseView.swift
import OpenrowDBCore
import SwiftUI

/// Schema browser for a connected database: searchable table list (grouped by
/// schema, with row counts) on the left, a sortable paged results grid on the right.
struct BrowseView: View {
    @Environment(ConnectionManager.self) private var manager
    let connectionID: UUID

    private static let pageSizeOptions = [50, 100, 200, 500]

    @State private var pageSize = 100
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
    @State private var selectedRowID: Int?
    @State private var showRowInspector = false

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
            selectedRowID = nil
            Task {
                await loadCount()
                await loadRows()
            }
        }
        .onChange(of: page) {
            selectedRowID = nil
            Task { await loadRows() }
        }
        .onChange(of: sortOrder) {
            page = 0
            Task { await loadRows() }
        }
        .onChange(of: pageSize) {
            page = 0
            Task { await loadRows() }
        }
        .onChange(of: selectedRowID) {
            if selectedRowID != nil { showRowInspector = true }
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
                .help("Refresh (⌘R)")
                .keyboardShortcut("r", modifiers: .command)
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
                ResultsTable(result: result, sortOrder: $sortOrder, selection: $selectedRowID)
                Divider()
                paginationBar
            }
            .inspector(isPresented: $showRowInspector) {
                RowInspector(result: result, selectedRowID: selectedRowID)
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 460)
            }
        } else {
            Color.clear
        }
    }

    private var firstRowIndex: Int { page * pageSize + 1 }
    private var lastRowIndex: Int { page * pageSize + (result?.rows.count ?? 0) }
    private var totalPages: Int {
        guard let totalRows, totalRows > 0 else { return 1 }
        return (totalRows + pageSize - 1) / pageSize
    }
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

            if totalRows != nil {
                Text("Page")
                    .font(.callout).foregroundStyle(.secondary)
                PageJumpField(page: $page, totalPages: totalPages)
                Text("of \(totalPages)")
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }

            Text(rangeLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if loadingRows {
                ProgressView().controlSize(.small)
            }

            Spacer()

            Picker("Rows", selection: $pageSize) {
                ForEach(Self.pageSizeOptions, id: \.self) { size in
                    Text("\(size) / page").tag(size)
                }
            }
            .labelsHidden()
            .frame(width: 110)

            Button {
                showRowInspector.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle row detail")
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

/// A 1-based page number field that jumps on commit, clamped to [1, totalPages].
private struct PageJumpField: View {
    @Binding var page: Int
    let totalPages: Int

    @State private var text: String = ""

    var body: some View {
        TextField("", text: $text)
            .frame(width: 44)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .onAppear { text = "\(page + 1)" }
            .onChange(of: page) { text = "\(page + 1)" }
            .onSubmit { commit() }
    }

    private func commit() {
        guard let value = Int(text) else {
            text = "\(page + 1)"
            return
        }
        let clamped = min(max(value, 1), totalPages)
        page = clamped - 1
        text = "\(clamped)"
    }
}

/// Trailing inspector showing every column/value of the selected row, copyable.
private struct RowInspector: View {
    let result: QueryResult
    let selectedRowID: Int?

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
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            valueText(row.indices.contains(index) ? row[index] : nil)
                                .textSelection(.enabled)
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

    @ViewBuilder
    private func valueText(_ value: String?) -> some View {
        if let value {
            Text(value).monospaced().font(.callout).textSelection(.enabled)
        } else {
            Text("NULL").foregroundStyle(.secondary).italic()
        }
    }
}
