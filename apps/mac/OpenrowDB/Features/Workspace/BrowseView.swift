// BrowseView.swift
import OpenrowDBCore
import SwiftUI

/// Schema browser for a connected database: searchable table list (grouped by
/// schema, with row counts) on the left, a sortable paged results grid on the right.
struct BrowseView: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(WorkspaceTabsState.self) private var tabs
    let connectionID: UUID

    private static let pageSizeOptions = [50, 100, 200, 500]

    @State private var pageSize = 100
    @State private var tables: [TableRef] = []
    @State private var tableCounts: [TableRef.ID: RowCount] = [:]
    @State private var tablesError: String?
    @State private var loadingTables = false
    @State private var search = ""

    @State private var selectedTableID: TableRef.ID?
    @State private var result: QueryResult?
    @State private var rowsError: String?
    @State private var loadingRows = false
    @State private var page = 0
    @State private var totalRows: RowCount?
    @State private var sortOrder: [ColumnComparator] = []
    @State private var selectedRowID: Int?
    @State private var showRowInspector = false
    @State private var columnTypes: [String: String] = [:]

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
            columnTypes = [:]
            Task {
                await loadColumns()
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
                            Label(table.name, systemImage: table.kind == .view ? "eye" : "tablecells")
                                .badge(badgeText(for: table))
                                .help(helpText(for: table))
                                .tag(table.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    tabs.openTableTab(table, for: connectionID)
                                }
                                .contextMenu {
                                    Button("Open in New Tab") {
                                        tabs.openTableTab(table, for: connectionID)
                                    }
                                    Button("Copy Name") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(table.name, forType: .string)
                                    }
                                    Button("Copy Qualified Name") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString("\(table.schema).\(table.name)", forType: .string)
                                    }
                                }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func badgeText(for table: TableRef) -> String? {
        guard let count = tableCounts[table.id] else { return nil }
        let prefix = count.isEstimate ? "~" : ""
        return "\(prefix)\(count.value)"
    }

    private func helpText(for table: TableRef) -> String {
        let suffix = table.kind == .view ? " (view)" : ""
        return "\(table.schema).\(table.name)\(suffix)"
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
        // For estimates (big tables) the total may be off, so fall back to whether
        // the current page came back full; for exact counts use the total.
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

    /// Load row counts for every table badge, in the background. Hybrid: large
    /// tables use the instant catalog estimate (shown as "~N"); small or
    /// un-analyzed tables get an exact COUNT — so no big table is ever scanned.
    private func loadCounts() async {
        for table in tables {
            if let count = try? await manager.rowCount(of: table, on: connectionID) {
                tableCounts[table.id] = count
            }
        }
    }

    /// Count for the selected table (drives the pager total): exact when cheap,
    /// estimate when the table is large.
    private func loadCount() async {
        guard let selectedTable else { return }
        totalRows = try? await manager.rowCount(of: selectedTable, on: connectionID)
    }

    private func loadColumns() async {
        guard let selectedTable else { return }
        if let infos = try? await manager.columns(of: selectedTable, on: connectionID) {
            columnTypes = Dictionary(infos.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        }
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

// MARK: - Pagination

/// A 1-based page number field that jumps on commit, clamped to [1, totalPages].
struct PageJumpField: View {
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
