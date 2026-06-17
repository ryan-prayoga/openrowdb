// TableDataView.swift
import OpenrowDBCore
import SwiftUI

/// The data pane for a single table: a search bar + row actions on top, a
/// sortable paged results grid, a pagination bar, and a row inspector. Owns all
/// loading (rows, count, columns, primary keys) plus row insert / edit / delete.
///
/// Shared by the schema browser's right pane and the standalone table tab so row
/// browsing + editing lives in exactly one place.
struct TableDataView: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(WorkspaceTabsState.self) private var tabs
    @Environment(RefreshCoordinator.self) private var refreshCoordinator
    let connectionID: UUID
    let table: TableRef
    var leadingInset: CGFloat = 0
    /// Called after a successful insert / update / delete so the host (e.g. the
    /// browser's table list) can refresh row-count badges.
    var onMutated: () -> Void = {}

    private static let pageSizeOptions = [50, 100, 200, 500]
    private static let searchDebounce: Duration = .milliseconds(300)

    @State private var pageSize = 100
    @State private var page = 0
    @State private var result: QueryResult?
    @State private var rowsError: String?
    @State private var loadingRows = false
    @State private var totalRows: RowCount?
    @State private var sortOrder: [ColumnComparator] = []
    @State private var selectedRowID: Int?
    @State private var showRowInspector = false
    @State private var columns: [ColumnInfo] = []
    @State private var columnTypes: [String: String] = [:]
    @State private var primaryKeys: [String] = []
    @State private var foreignKeys: [ForeignKeyRef] = []

    @State private var search = ""
    @State private var appliedSearch = ""
    @State private var searchGeneration: UInt64 = 0

    @State private var filterColumn = ""
    @State private var filterValue = ""
    @State private var appliedFilterColumn = ""
    @State private var appliedFilterValue = ""
    @State private var filterGeneration: UInt64 = 0

    // Per-loader generation tokens: each load increments its own counter and
    // only commits if still current, so an out-of-order completion from an
    // earlier (slower) load can't overwrite a newer one's result/count.
    @State private var rowsGeneration = 0
    @State private var countGeneration = 0

    @State private var pendingDeleteRow: Int?
    @State private var mutationError: String?
    @State private var isResetting = false

    // Add-row panel state (edit is handled inline in the grid via editState)
    @State private var inlineEditorMode: InlineRowEditorPanel.Mode?
    @State private var inlineEditorFields: [InlineRowEditorPanel.FieldState] = []
    // Inline edit state — shared with ResultsGrid cells via @Observable
    @State private var editState = InlineEditState()

    private var canMutate: Bool { table.kind == .table && !manager.isReadOnly(connectionID) }
    /// Per-row edit/delete needs a primary key to target exactly one row. Without
    /// one we'd have to match on rendered cell text, which doesn't reliably round
    /// trip (floats, timestamps, json) — so those actions are disabled instead.
    private var canEditRows: Bool { canMutate && !primaryKeys.isEmpty }
    private var isSearching: Bool { !appliedSearch.isEmpty && !columns.isEmpty }
    private var isColumnFiltering: Bool {
        !appliedFilterColumn.isEmpty && !appliedFilterValue.isEmpty && !columns.isEmpty
    }
    private var isFiltered: Bool { isSearching || isColumnFiltering }

    private var dialect: SQLDialect {
        manager.connections.first(where: { $0.id == connectionID })?.driver.dialect ?? .postgres
    }

    private var mutationErrorPresented: Binding<Bool> {
        Binding(get: { mutationError != nil }, set: { if !$0 { mutationError = nil } })
    }

    private var currentSort: SortSpec? {
        sortOrder.first.map { SortSpec(column: $0.columnName, ascending: $0.order == .forward) }
    }

    var body: some View {
        observedContent
    }

    private var observedContent: some View {
        contentWithDialogs
            .task(id: table.id) { await resetAndLoad() }
            .onChange(of: refreshCoordinator.signal(for: connectionID)) { _, _ in
                Task { await refreshCurrentPage() }
            }
            .onChange(of: page) { handlePageChange() }
            .onChange(of: sortOrder) { handleSortChange() }
            .onChange(of: pageSize) { handlePageSizeChange() }
            .onChange(of: search) { handleSearchChange() }
            .onChange(of: filterValue) { handleFilterChange() }
            .onChange(of: filterColumn) { handleFilterChange() }
            .onChange(of: selectedRowID) { previous, current in
                handleSelectionChange(previous: previous, current: current)
            }
    }

    private var contentWithDialogs: some View {
        content
            .confirmationDialog(
                "Delete this row?",
                isPresented: deleteDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { confirmDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the row. This can't be undone.")
            }
            .alert("Operation failed", isPresented: mutationErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mutationError ?? "")
            }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(get: { pendingDeleteRow != nil }, set: { if !$0 { pendingDeleteRow = nil } })
    }

    private func handlePageChange() {
        guard !isResetting else { return }
        selectedRowID = nil
        Task { await loadRows() }
    }

    private func handleSortChange() {
        guard !isResetting else { return }
        page = 0
        Task { await loadRows() }
    }

    private func handlePageSizeChange() {
        guard !isResetting else { return }
        page = 0
        Task { await loadRows() }
    }

    private func handleSearchChange() {
        guard !isResetting else { return }
        scheduleSearch()
    }

    private func handleFilterChange() {
        guard !isResetting else { return }
        scheduleColumnFilter()
    }

    private func handleSelectionChange(previous: Int?, current: Int?) {
        if previous == nil, current != nil { showRowInspector = true }
        if let editingRow = editState.rowID, current != editingRow {
            cancelInlineEdit()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let rowsError {
            PlaceholderView(
                title: "Query failed",
                subtitle: rowsError,
                systemImage: "exclamationmark.triangle",
                variant: .error
            )
        } else if loadingRows && result == nil && columns.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                actionBar
                Divider()
                grid
            }
            .animation(.easeInOut(duration: 0.18), value: inlineEditorMode != nil)
        }
    }

    @ViewBuilder
    private var grid: some View {
        if let result, !result.columns.isEmpty {
            VStack(spacing: 0) {
                ResultsGrid(
                    result: result,
                    sortOrder: $sortOrder,
                    selection: $selectedRowID,
                    leadingInset: leadingInset,
                    canMutate: canMutate,
                    inlineEdit: editState.rowID != nil ? editState : nil,
                    onCommitEdit: { commitInlineEdit() },
                    onCancelEdit: { cancelInlineEdit() },
                    onDoubleClick: { id in
                        selectedRowID = id
                        if canEditRows { beginEditRow() }
                    },
                    onEdit: { id in
                        selectedRowID = id
                        if canEditRows { beginEditRow() }
                    },
                    onDelete: { id in
                        if canEditRows { pendingDeleteRow = id }
                    },
                    onDuplicate: { id in
                        if canMutate { duplicateRow(id) }
                    },
                    sqlCopy: canMutate ? RowSQLCopyContext(table: table, dialect: dialect, primaryKeys: primaryKeys) : nil
                )
                if let mode = inlineEditorMode {
                    Divider()
                    InlineRowEditorPanel(
                        mode: mode,
                        fields: $inlineEditorFields,
                        onSave: { try await performInlineSave() },
                        onCancel: { inlineEditorMode = nil }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Divider()
                paginationBar
            }
            .inspector(isPresented: $showRowInspector) {
                RowInspector(
                    result: result,
                    selectedRowID: selectedRowID,
                    columnTypes: columnTypes,
                    foreignKeys: foreignKeys,
                    onFollowFK: followForeignKey
                )
                .inspectorColumnWidth(min: 240, ideal: 300, max: 460)
            }
        } else if loadingRows {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if totalRows?.value == 0 {
            PlaceholderView(
                title: isFiltered ? "No matches" : "No rows yet",
                subtitle: emptyFilterSubtitle,
                systemImage: isFiltered ? "magnifyingglass" : "tablecells"
            )
        } else {
            Color.clear
        }
    }

    // MARK: - Action bar

    private var emptyFilterSubtitle: String {
        if isColumnFiltering {
            return "Nothing in \(appliedFilterColumn) matches \"\(appliedFilterValue)\"."
        }
        if isSearching {
            return "Nothing matches \"\(appliedSearch)\"."
        }
        return "This table is empty."
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search rows", text: $search)
                    .textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: .rect(cornerRadius: 7))
            .frame(maxWidth: 280)

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.secondary)
                Picker("Column", selection: $filterColumn) {
                    Text("Column").tag("")
                    ForEach(columns, id: \.name) { col in
                        Text(col.name).tag(col.name)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                TextField("Filter value", text: $filterValue)
                    .textFieldStyle(.plain)
                    .disabled(filterColumn.isEmpty)
                if !filterValue.isEmpty || !filterColumn.isEmpty {
                    Button {
                        filterColumn = ""
                        filterValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary, in: .rect(cornerRadius: 7))
            .frame(maxWidth: 320)

            Spacer()

            if manager.isReadOnly(connectionID) {
                Label("Read-only", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if canMutate {
                if editState.rowID != nil {
                    Button { cancelInlineEdit() } label: { Label("Cancel", systemImage: "xmark") }
                        .keyboardShortcut(.cancelAction)
                    Button { commitInlineEdit() } label: { Label("Save", systemImage: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button { beginAddRow() } label: { Label("Add Row", systemImage: "plus") }
                        .help("Insert a new row")
                    Button { beginEditRow() } label: { Label("Edit", systemImage: "pencil") }
                        .labelStyle(.iconOnly)
                        .disabled(selectedRowID == nil || !canEditRows)
                        .help(rowActionHelp("Edit selected row"))
                    Button { pendingDeleteRow = selectedRowID } label: { Label("Delete", systemImage: "trash") }
                        .labelStyle(.iconOnly)
                        .disabled(selectedRowID == nil || !canEditRows)
                        .help(rowActionHelp("Delete selected row"))
                }
            }
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Pagination

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

    // MARK: - Foreign keys

    private func followForeignKey(_ fk: ForeignKeyRef, value: String) {
        tabs.openTableTab(
            fk.referencedTable,
            for: connectionID,
            filterColumn: fk.referencedColumn,
            filterValue: value
        )
    }

    // MARK: - Row editing

    private func duplicateRow(_ index: Int) {
        guard canMutate else { return }
        cancelInlineEdit()
        let initial = initialValues(forRowAt: index)
        inlineEditorFields = columns.enumerated().map { i, col in
            if primaryKeys.contains(col.name) {
                return InlineRowEditorPanel.FieldState(id: i, name: col.name, type: col.type, entry: .useDefault, text: "")
            }
            let val = initial[col.name] ?? nil
            if let v = val {
                return InlineRowEditorPanel.FieldState(id: i, name: col.name, type: col.type, entry: .value, text: v)
            }
            return InlineRowEditorPanel.FieldState(id: i, name: col.name, type: col.type, entry: .null, text: "")
        }
        inlineEditorMode = .add
    }

    private func beginAddRow() {
        cancelInlineEdit()
        inlineEditorFields = buildFields(mode: .add, initialByName: [:])
        inlineEditorMode = .add
    }

    private func beginEditRow() {
        inlineEditorMode = nil
        guard let index = selectedRowID, let preds = predicates(forRowAt: index) else { return }
        editState.predicates = preds
        editState.values = initialValues(forRowAt: index)
        editState.rowID = index
    }

    private func commitInlineEdit() {
        guard editState.rowID != nil else { return }
        let assignments = columns.map { col -> (column: String, value: SQLValue) in
            let outer = editState.values[col.name]
            if let outer, let inner = outer { return (col.name, .text(inner)) }
            return (col.name, .null)
        }
        let preds = editState.predicates
        cancelInlineEdit()
        Task {
            do {
                try await manager.updateRow(table, on: connectionID, assignments: assignments, predicates: preds)
                await reloadAfterMutation(clearSelection: false)
            } catch {
                mutationError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            }
        }
    }

    private func cancelInlineEdit() {
        editState.rowID = nil
        editState.values = [:]
        editState.predicates = []
    }

    private func buildFields(
        mode: InlineRowEditorPanel.Mode,
        initialByName: [String: String?]
    ) -> [InlineRowEditorPanel.FieldState] {
        columns.enumerated().map { index, col in
            let entry: InlineRowEditorPanel.FieldState.Entry
            var text = ""
            switch mode {
            case .add:
                entry = primaryKeys.contains(col.name) ? .useDefault : .value
            case .edit:
                let current = initialByName[col.name] ?? nil
                if let current {
                    entry = .value
                    text = current
                } else {
                    entry = .null
                }
            }
            return InlineRowEditorPanel.FieldState(id: index, name: col.name, type: col.type, entry: entry, text: text)
        }
    }

    private func performInlineSave() async throws {
        guard inlineEditorMode == .add else { return }
        let active = inlineEditorFields.filter { $0.entry != .useDefault }
        let cols = active.map(\.name)
        let vals = active.map { $0.entry == .null ? SQLValue.null : .text($0.text) }
        try await manager.insertRow(into: table, on: connectionID, columns: cols, values: vals)
        inlineEditorMode = nil
        await reloadAfterMutation(clearSelection: true)
    }

    private func confirmDelete() {
        guard let index = pendingDeleteRow, let predicates = predicates(forRowAt: index) else { return }
        pendingDeleteRow = nil
        Task {
            do {
                try await manager.deleteRow(table, on: connectionID, predicates: predicates)
                await reloadAfterMutation(clearSelection: true)
            } catch {
                mutationError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            }
        }
    }

    /// Column values of the selected row, keyed by column name (nil = SQL NULL).
    private func initialValues(forRowAt index: Int) -> [String: String?] {
        guard let result, result.rows.indices.contains(index) else { return [:] }
        let row = result.rows[index]
        var values: [String: String?] = [:]
        for (columnIndex, name) in result.columns.enumerated() {
            values[name] = row.indices.contains(columnIndex) ? row[columnIndex] : nil
        }
        return values
    }

    /// WHERE predicates identifying a row by its primary key. Returns nil when
    /// the table has no primary key (edit/delete are disabled in that case) or a
    /// key column isn't in the current result set.
    private func predicates(forRowAt index: Int) -> [(column: String, value: SQLValue)]? {
        guard !primaryKeys.isEmpty else { return nil }
        guard let result, result.rows.indices.contains(index) else { return nil }
        let row = result.rows[index]
        var predicates: [(column: String, value: SQLValue)] = []
        for column in primaryKeys {
            guard let columnIndex = result.columns.firstIndex(of: column) else { return nil }
            let cell = row.indices.contains(columnIndex) ? row[columnIndex] : nil
            predicates.append((column: column, value: cell.map(SQLValue.text) ?? .null))
        }
        return predicates
    }

    private func rowActionHelp(_ enabled: String) -> String {
        canEditRows ? enabled : "Needs a primary key to identify the row"
    }

    // MARK: - Loading

    private func resetAndLoad() async {
        isResetting = true
        searchGeneration += 1
        filterGeneration += 1
        page = 0
        sortOrder = []
        result = nil
        totalRows = nil
        selectedRowID = nil
        columns = []
        columnTypes = [:]
        primaryKeys = []
        search = ""
        appliedSearch = ""
        filterColumn = ""
        filterValue = ""
        appliedFilterColumn = ""
        appliedFilterValue = ""
        if let preset = tabs.tableFilter(for: table) {
            filterColumn = preset.column
            filterValue = preset.value
            appliedFilterColumn = preset.column
            appliedFilterValue = preset.value
        }
        await loadColumns()
        await loadKeys()
        await loadForeignKeys()
        await loadCount()
        await loadRows()
        isResetting = false
    }

    private func scheduleSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        Task {
            try? await Task.sleep(for: Self.searchDebounce)
            guard generation == searchGeneration else { return }
            appliedSearch = search
            page = 0
            selectedRowID = nil
            await loadCount()
            await loadRows()
        }
    }

    private func scheduleColumnFilter() {
        filterGeneration += 1
        let generation = filterGeneration
        Task {
            try? await Task.sleep(for: Self.searchDebounce)
            guard generation == filterGeneration else { return }
            appliedFilterColumn = filterColumn
            appliedFilterValue = filterValue
            page = 0
            selectedRowID = nil
            await loadCount()
            await loadRows()
        }
    }

    private func reloadAfterMutation(clearSelection: Bool) async {
        if clearSelection { selectedRowID = nil }
        await loadCount()
        await loadRows()
        onMutated()
    }

    /// ⌘R refresh — reload metadata and the current page without resetting
    /// pagination, sort order, or the active search.
    private func refreshCurrentPage() async {
        await loadColumns()
        await loadKeys()
        await loadForeignKeys()
        await loadCount()
        await loadRows()
    }

    private func loadColumns() async {
        if let infos = try? await manager.columns(of: table, on: connectionID) {
            columns = infos
            columnTypes = Dictionary(infos.map { ($0.name, $0.type) }, uniquingKeysWith: { first, _ in first })
        }
    }

    private func loadKeys() async {
        guard table.kind == .table else { return }
        primaryKeys = (try? await manager.primaryKeyColumns(of: table, on: connectionID)) ?? []
    }

    private func loadForeignKeys() async {
        guard table.kind == .table else { return }
        foreignKeys = (try? await manager.foreignKeys(of: table, on: connectionID)) ?? []
    }

    private func loadCount() async {
        countGeneration += 1
        let generation = countGeneration
        let value: RowCount?
        if isColumnFiltering {
            let count = try? await manager.filterRowCount(
                table, on: connectionID, column: appliedFilterColumn, term: appliedFilterValue
            )
            value = count.map { RowCount(value: $0, isEstimate: false) }
        } else if isSearching {
            let count = try? await manager.searchRowCount(table, on: connectionID, columns: columns.map(\.name), term: appliedSearch)
            value = count.map { RowCount(value: $0, isEstimate: false) }
        } else {
            value = try? await manager.rowCount(of: table, on: connectionID)
        }
        guard generation == countGeneration else { return }
        totalRows = value
    }

    private func loadRows() async {
        // Selection is a row index into the *current* page; any reload (sort,
        // page, page-size, search, post-mutation) invalidates it, so clear it
        // first — otherwise Edit/Delete could target the wrong row.
        selectedRowID = nil
        rowsGeneration += 1
        let generation = rowsGeneration
        loadingRows = true
        rowsError = nil
        defer { if generation == rowsGeneration { loadingRows = false } }
        do {
            let fetched: QueryResult
            if isColumnFiltering {
                fetched = try await manager.filterRows(
                    table,
                    on: connectionID,
                    column: appliedFilterColumn,
                    term: appliedFilterValue,
                    limit: pageSize,
                    offset: page * pageSize,
                    sort: currentSort
                )
            } else if isSearching {
                fetched = try await manager.searchRows(
                    table,
                    on: connectionID,
                    columns: columns.map(\.name),
                    term: appliedSearch,
                    limit: pageSize,
                    offset: page * pageSize,
                    sort: currentSort
                )
            } else {
                fetched = try await manager.fetchRows(
                    table,
                    on: connectionID,
                    limit: pageSize,
                    offset: page * pageSize,
                    sort: currentSort
                )
            }
            guard generation == rowsGeneration else { return }
            result = fetched
        } catch {
            guard generation == rowsGeneration else { return }
            rowsError = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            result = nil
        }
    }
}

// MARK: - Inline row editor panel

struct InlineRowEditorPanel: View {
    enum Mode: Equatable { case add, edit }

    struct FieldState: Identifiable {
        enum Entry: Equatable { case value, null, useDefault }
        let id: Int
        let name: String
        let type: String
        var entry: Entry
        var text: String
    }

    let mode: Mode
    @Binding var fields: [FieldState]
    let onSave: () async throws -> Void
    let onCancel: () -> Void

    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            fieldScroll
        }
        .background(.regularMaterial)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .add ? "plus.square.fill" : "pencil.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(mode == .add ? "New Row" : "Edit Row").fontWeight(.medium)
            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(1)
            }
            Spacer()
            if saving { ProgressView().controlSize(.small) }
            Button("Cancel") {
                errorMessage = nil
                onCancel()
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
            Button(mode == .add ? "Insert" : "Save") { triggerSave() }
                .buttonStyle(.glassProminent)
                .disabled(saving)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var fieldScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach($fields) { $field in
                    fieldCell($field)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 120)
    }

    @ViewBuilder
    private func fieldCell(_ field: Binding<FieldState>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.wrappedValue.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(field.wrappedValue.type)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            switch field.wrappedValue.entry {
            case .value:
                TextField("value", text: field.text)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
            case .null:
                Text("NULL")
                    .italic()
                    .foregroundStyle(.secondary)
                    .frame(width: 150, height: 22, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background(.quaternary, in: .rect(cornerRadius: 5))
            case .useDefault:
                Text("Default")
                    .italic()
                    .foregroundStyle(.secondary)
                    .frame(width: 150, height: 22, alignment: .leading)
                    .padding(.horizontal, 6)
                    .background(.quaternary, in: .rect(cornerRadius: 5))
            }

            Menu {
                Button("Value") { field.wrappedValue.entry = .value }
                Button("NULL") { field.wrappedValue.entry = .null }
                if mode == .add {
                    Button("Default") { field.wrappedValue.entry = .useDefault }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(entryLabel(field.wrappedValue.entry))
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func entryLabel(_ entry: FieldState.Entry) -> String {
        switch entry {
        case .value: return "Value"
        case .null: return "NULL"
        case .useDefault: return "Default"
        }
    }

    private func triggerSave() {
        saving = true
        errorMessage = nil
        Task {
            do {
                try await onSave()
            } catch {
                errorMessage = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            }
            saving = false
        }
    }
}
