// BrowseView.swift
import OpenrowDBCore
import SwiftUI

/// Schema browser for a connected database: table list on the left, a paged
/// results grid on the right.
struct BrowseView: View {
    @Environment(ConnectionManager.self) private var manager
    let connectionID: UUID

    private let pageSize = 100

    @State private var tables: [TableRef] = []
    @State private var tablesError: String?
    @State private var loadingTables = false

    @State private var selectedTableID: TableRef.ID?
    @State private var result: QueryResult?
    @State private var rowsError: String?
    @State private var loadingRows = false
    @State private var page = 0
    @State private var totalRows: Int?

    private var selectedTable: TableRef? {
        tables.first { $0.id == selectedTableID }
    }

    var body: some View {
        HSplitView {
            tableList
                .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

            resultsPane
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: connectionID) { await loadTables() }
        .onChange(of: selectedTableID) {
            page = 0
            result = nil
            totalRows = nil
            Task {
                await loadCount()
                await loadRows()
            }
        }
        .onChange(of: page) {
            Task { await loadRows() }
        }
    }

    // MARK: - Table list

    @ViewBuilder
    private var tableList: some View {
        if loadingTables {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let tablesError {
            ContentUnavailableView("Couldn't load tables", systemImage: "exclamationmark.triangle", description: Text(tablesError))
        } else if tables.isEmpty {
            ContentUnavailableView("No tables", systemImage: "tablecells")
        } else {
            List(tables, selection: $selectedTableID) { table in
                Label(table.name, systemImage: "tablecells")
                    .help("\(table.schema).\(table.name)")
                    .tag(table.id)
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
                ResultsTable(result: result)
                Divider()
                paginationBar
            }
        } else {
            Color.clear
        }
    }

    /// 1-based index of the first row on the current page.
    private var firstRowIndex: Int { page * pageSize + 1 }
    /// 1-based index of the last row on the current page.
    private var lastRowIndex: Int { page * pageSize + (result?.rows.count ?? 0) }
    /// Whether a next page exists, based on the known total.
    private var hasNextPage: Bool {
        guard let totalRows else { return (result?.rows.count ?? 0) == pageSize }
        return (page + 1) * pageSize < totalRows
    }

    private var paginationBar: some View {
        HStack(spacing: 12) {
            Button {
                page -= 1
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(page == 0 || loadingRows)
            .labelStyle(.iconOnly)

            Button {
                page += 1
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
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

    private func loadTables() async {
        loadingTables = true
        tablesError = nil
        defer { loadingTables = false }
        do {
            tables = try await manager.tables(on: connectionID)
        } catch {
            tablesError = String(describing: error)
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
                offset: page * pageSize
            )
        } catch {
            rowsError = String(describing: error)
            result = nil
        }
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

/// A SwiftUI `Table` with columns derived dynamically from a `QueryResult`.
private struct ResultsTable: View {
    let result: QueryResult

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
            Table(rows) {
                TableColumnForEach(columns) { column in
                    TableColumn(column.name) { row in
                        cell(row.cells.indices.contains(column.id) ? row.cells[column.id] : nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cell(_ value: String?) -> some View {
        if let value {
            Text(value).monospaced()
        } else {
            Text("NULL").foregroundStyle(.secondary).italic()
        }
    }
}
