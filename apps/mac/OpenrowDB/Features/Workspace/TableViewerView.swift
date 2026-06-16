// TableViewerView.swift
import OpenrowDBCore
import SwiftUI

struct TableViewerView: View {
    @Environment(ConnectionManager.self) private var manager
    let connectionID: UUID
    let table: TableRef

    private static let pageSizeOptions = [50, 100, 200, 500]

    @State private var pageSize = 100
    @State private var page = 0
    @State private var result: QueryResult?
    @State private var rowsError: String?
    @State private var loadingRows = false
    @State private var totalRows: RowCount?
    @State private var sortOrder: [ColumnComparator] = []
    @State private var selectedRowID: Int?
    @State private var showRowInspector = false
    @State private var columnTypes: [String: String] = [:]

    private var currentSort: SortSpec? {
        sortOrder.first.map { SortSpec(column: $0.columnName, ascending: $0.order == .forward) }
    }

    var body: some View {
        content
            .task(id: table.id) {
                page = 0
                sortOrder = []
                result = nil
                totalRows = nil
                selectedRowID = nil
                columnTypes = [:]
                await loadColumns()
                await loadCount()
                await loadRows()
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

    @ViewBuilder
    private var content: some View {
        if loadingRows && result == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let rowsError {
            ContentUnavailableView("Query failed", systemImage: "exclamationmark.triangle", description: Text(rowsError))
        } else if totalRows?.value == 0 {
            ContentUnavailableView("No rows", systemImage: "tablecells")
        } else if let result, !result.columns.isEmpty {
            VStack(spacing: 0) {
                ResultsGrid(result: result, sortOrder: $sortOrder, selection: $selectedRowID)
                Divider()
                paginationBar
            }
            .inspector(isPresented: $showRowInspector) {
                RowInspector(result: result, selectedRowID: selectedRowID, columnTypes: columnTypes)
                    .inspectorColumnWidth(min: 240, ideal: 300, max: 460)
            }
        } else {
            Color.clear
        }
    }

    private var firstRowIndex: Int { page * pageSize + 1 }
    private var lastRowIndex: Int { page * pageSize + (result?.rows.count ?? 0) }
    private var totalPages: Int {
        guard let totalRows, totalRows.value > 0 else { return 1 }
        return (totalRows.value + pageSize - 1) / pageSize
    }
    private var hasNextPage: Bool {
        guard let totalRows, !totalRows.isEstimate else {
            return (result?.rows.count ?? 0) == pageSize
        }
        return (page + 1) * pageSize < totalRows.value
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
            let prefix = totalRows.isEstimate ? "~" : ""
            return "\(firstRowIndex)–\(lastRowIndex) of \(prefix)\(totalRows.value)"
        }
        return "\(firstRowIndex)–\(lastRowIndex)"
    }

    private func loadColumns() async {
        if let infos = try? await manager.columns(of: table, on: connectionID) {
            columnTypes = Dictionary(infos.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private func loadCount() async {
        totalRows = try? await manager.rowCount(of: table, on: connectionID)
    }

    private func loadRows() async {
        loadingRows = true
        rowsError = nil
        defer { loadingRows = false }
        do {
            result = try await manager.fetchRows(
                table,
                on: connectionID,
                limit: pageSize,
                offset: page * pageSize,
                sort: currentSort
            )
        } catch {
            rowsError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            result = nil
        }
    }
}
