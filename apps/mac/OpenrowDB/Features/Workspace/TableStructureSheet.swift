// TableStructureView.swift
// Inline structure editor — opens as a workspace tab, not a modal sheet.
import OpenrowDBCore
import SwiftUI

struct TableStructureView: View {
    enum Mode: Equatable { case create, edit }

    let connectionID: UUID
    let mode: Mode
    let dialect: SQLDialect
    var database: String = ""
    var schemas: [String] = []
    var defaultSchema: String = "public"
    var existingTable: TableRef?
    let onSaved: (TableRef) -> Void
    let onCancel: () -> Void

    @Environment(ConnectionManager.self) private var manager

    @State private var schema: String
    @State private var name: String
    @State private var originalName: String
    @State private var columns: [ColumnDefinition]
    @State private var originalColumns: [ColumnDefinition] = []
    @State private var loading = false
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var pendingDropColumns: [String] = []
    @State private var showDDLPreview = false

    @State private var indexes: [IndexRef] = []
    @State private var foreignKeys: [ForeignKeyRef] = []
    @State private var newIndexName = ""
    @State private var newIndexColumn = ""
    @State private var newIndexUnique = false
    @State private var newFKName = ""
    @State private var newFKColumn = ""
    @State private var newFKRefSchema = ""
    @State private var newFKRefTable = ""
    @State private var newFKRefColumn = ""

    init(
        connectionID: UUID,
        mode: Mode,
        dialect: SQLDialect,
        database: String = "",
        schemas: [String] = [],
        defaultSchema: String = "public",
        existingTable: TableRef? = nil,
        onSaved: @escaping (TableRef) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.connectionID = connectionID
        self.mode = mode
        self.dialect = dialect
        self.database = database
        self.schemas = schemas
        self.defaultSchema = defaultSchema
        self.existingTable = existingTable
        self.onSaved = onSaved
        self.onCancel = onCancel

        _schema = State(initialValue: existingTable?.schema ?? defaultSchema)
        _name = State(initialValue: existingTable?.name ?? "")
        _originalName = State(initialValue: existingTable?.name ?? "")
        if mode == .create {
            _columns = State(initialValue: [
                ColumnDefinition(name: "id", type: dialect == .postgres ? "serial" : "int",
                                 isNullable: false, isPrimaryKey: true)
            ])
        } else {
            _columns = State(initialValue: [])
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var namedColumns: [ColumnDefinition] {
        columns.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }
    private var canSave: Bool {
        guard !trimmedName.isEmpty, !saving else { return false }
        return mode == .edit || !namedColumns.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                editorBody
            }
        }
        .task {
            if mode == .edit { await loadExisting() }
        }
        .confirmationDialog(
            "Drop \(pendingDropColumns.count) column\(pendingDropColumns.count == 1 ? "" : "s")?",
            isPresented: Binding(get: { !pendingDropColumns.isEmpty }, set: { if !$0 { pendingDropColumns = [] } }),
            titleVisibility: .visible
        ) {
            Button("Drop & Save", role: .destructive) {
                pendingDropColumns = []
                performSave()
            }
            Button("Cancel", role: .cancel) { pendingDropColumns = [] }
        } message: {
            Text("Removing \(pendingDropColumns.joined(separator: ", ")) permanently deletes that column's data. This can't be undone.")
        }
        .sheet(isPresented: $showDDLPreview) {
            DDLPreviewSheet(statements: previewStatements)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(mode == .create ? "New Table" : "Edit Structure")
                .font(.headline)
            Spacer()
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(1)
            }
            if saving { ProgressView().controlSize(.small) }
            Button("Preview SQL") { showDDLPreview = true }
                .buttonStyle(.glass)
                .disabled(previewStatements.isEmpty)
            Button("Cancel", role: .cancel) { onCancel() }
                .buttonStyle(.glass)
                .keyboardShortcut(.cancelAction)
            Button(mode == .create ? "Create Table" : "Save Changes") { save() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Editor body

    private var editorBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                tableNameSection
                columnsSection
                if mode == .edit {
                    indexesSection
                    foreignKeysSection
                }
            }
            .padding(20)
        }
    }

    private var tableNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if mode == .create, schemas.count > 1 {
                    Text("Schema").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                    Picker("", selection: $schema) {
                        ForEach(schemaOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Text("Table Name").foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                TextField("untitled_table", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
            }
        }
    }

    // MARK: - Columns section

    private var columnsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Columns").font(.headline)
                if mode == .edit {
                    Text("(add, remove & rename only)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    columns.append(ColumnDefinition())
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Add Column")
            }

            // Column header
            columnHeader

            // Column rows
            ForEach($columns) { $col in
                columnRow($col)
            }

            if columns.isEmpty {
                Text("No columns yet. Press + to add one.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("Name")
                .frame(width: 180, alignment: .leading)
            Text("Type")
                .frame(width: 180, alignment: .leading)
            Text("Nullable")
                .frame(width: 72, alignment: .center)
            Text("Default")
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            if mode == .create {
                Text("PK")
                    .frame(width: 48, alignment: .center)
            }
            Spacer().frame(width: 32)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func columnRow(_ column: Binding<ColumnDefinition>) -> some View {
        HStack(spacing: 0) {
            TextField("name", text: column.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 172)
                .padding(.trailing, 8)

            HStack(spacing: 0) {
                TextField("type", text: column.type)
                    .textFieldStyle(.roundedBorder)
                Menu {
                    ForEach(commonTypes, id: \.self) { type in
                        Button(type) { column.wrappedValue.type = type }
                    }
                } label: {
                    Image(systemName: "chevron.down").imageScale(.small)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Common types")
            }
            .frame(width: 172)
            .padding(.trailing, 8)

            Toggle("", isOn: column.isNullable)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .frame(width: 72, alignment: .center)

            TextField("default (optional)", text: Binding(
                get: { column.wrappedValue.defaultValue ?? "" },
                set: { column.wrappedValue.defaultValue = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding(.trailing, 8)

            if mode == .create {
                Toggle("", isOn: column.isPrimaryKey)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .frame(width: 48, alignment: .center)
            }

            Button(role: .destructive) {
                columns.removeAll { $0.id == column.wrappedValue.id }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .frame(width: 32, alignment: .center)
            .help("Remove column")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: 6))
    }

    // MARK: - Indexes

    private var indexesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Indexes").font(.headline)
            if indexes.isEmpty {
                Text("No secondary indexes.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(indexes) { index in
                    HStack(spacing: 8) {
                        Image(systemName: index.isUnique ? "key.fill" : "list.bullet")
                            .foregroundStyle(.secondary)
                        Text(index.name).font(.callout.monospaced())
                        Text(index.columns.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if index.isUnique {
                            Text("UNIQUE").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            Task { await dropIndex(index) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            HStack(spacing: 8) {
                TextField("index_name", text: $newIndexName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                Picker("Column", selection: $newIndexColumn) {
                    Text("Column…").tag("")
                    ForEach(columns, id: \.id) { Text($0.name).tag($0.name) }
                }
                .labelsHidden()
                .frame(width: 140)
                Toggle("Unique", isOn: $newIndexUnique)
                    .toggleStyle(.checkbox)
                Button("Add Index") { Task { await addIndex() } }
                    .buttonStyle(.glass)
                    .disabled(newIndexName.trimmingCharacters(in: .whitespaces).isEmpty || newIndexColumn.isEmpty)
            }
        }
    }

    // MARK: - Foreign keys

    private var foreignKeysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Foreign Keys").font(.headline)
            if foreignKeys.isEmpty {
                Text("No foreign keys.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(foreignKeys) { fk in
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.arrow.left")
                            .foregroundStyle(.secondary)
                        Text("\(fk.column) → \(fk.referencedTable.schema).\(fk.referencedTable.name).\(fk.referencedColumn)")
                            .font(.callout)
                        Spacer()
                        Button(role: .destructive) {
                            Task { await dropForeignKey(fk) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField("constraint_name", text: $newFKName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                    Picker("Column", selection: $newFKColumn) {
                        Text("Column…").tag("")
                        ForEach(columns, id: \.id) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                HStack(spacing: 8) {
                    TextField("ref_schema", text: $newFKRefSchema)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    TextField("ref_table", text: $newFKRefTable)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                    TextField("ref_column", text: $newFKRefColumn)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Button("Add FK") { Task { await addForeignKey() } }
                        .buttonStyle(.glass)
                        .disabled(!canAddForeignKey)
                }
            }
        }
    }

    private var canAddForeignKey: Bool {
        !newFKColumn.isEmpty
            && !newFKRefTable.trimmingCharacters(in: .whitespaces).isEmpty
            && !newFKRefColumn.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Helpers

    private var schemaOptions: [String] {
        var options = schemas
        if !options.contains(schema) { options.insert(schema, at: 0) }
        return options
    }

    private var commonTypes: [String] {
        switch dialect {
        case .postgres:
            return ["integer", "bigint", "serial", "text", "varchar(255)", "boolean",
                    "timestamptz", "date", "numeric", "double precision", "uuid", "jsonb"]
        case .mysql:
            return ["int", "bigint", "int AUTO_INCREMENT", "varchar(255)", "text", "tinyint(1)",
                    "datetime", "date", "decimal(10,2)", "double", "char(36)", "json"]
        }
    }

    // MARK: - Loading

    private func loadExisting() async {
        guard let table = existingTable else { return }
        loading = true
        defer { loading = false }
        guard let defs = try? await manager.columnDefinitions(of: table, on: connectionID) else {
            errorMessage = "Couldn't load columns."
            return
        }
        columns = defs
        originalColumns = defs
        indexes = (try? await manager.indexes(of: table, on: connectionID)) ?? []
        foreignKeys = (try? await manager.foreignKeys(of: table, on: connectionID)) ?? []
        newFKRefSchema = table.schema
    }

    private func addIndex() async {
        guard let table = existingTable else { return }
        let name = newIndexName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !newIndexColumn.isEmpty else { return }
        errorMessage = nil
        do {
            try await manager.createIndex(
                on: table,
                connection: connectionID,
                name: name,
                columns: [newIndexColumn],
                unique: newIndexUnique
            )
            newIndexName = ""
            newIndexColumn = ""
            newIndexUnique = false
            indexes = try await manager.indexes(of: table, on: connectionID)
        } catch {
            errorMessage = (error as? DatabaseError)?.userMessage ?? String(describing: error)
        }
    }

    private func dropIndex(_ index: IndexRef) async {
        guard let table = existingTable else { return }
        errorMessage = nil
        do {
            try await manager.dropIndex(named: index.name, from: table, on: connectionID)
            indexes = try await manager.indexes(of: table, on: connectionID)
        } catch {
            errorMessage = (error as? DatabaseError)?.userMessage ?? String(describing: error)
        }
    }

    private func addForeignKey() async {
        guard let table = existingTable else { return }
        let refSchema = newFKRefSchema.trimmingCharacters(in: .whitespaces).isEmpty
            ? table.schema : newFKRefSchema.trimmingCharacters(in: .whitespaces)
        let refTable = newFKRefTable.trimmingCharacters(in: .whitespaces)
        let refColumn = newFKRefColumn.trimmingCharacters(in: .whitespaces)
        let constraint = newFKName.trimmingCharacters(in: .whitespaces).isEmpty
            ? "fk_\(table.name)_\(newFKColumn)" : newFKName.trimmingCharacters(in: .whitespaces)
        let referenced = TableRef(database: table.database, schema: refSchema, name: refTable)
        errorMessage = nil
        do {
            try await manager.addForeignKey(
                on: table,
                connection: connectionID,
                constraintName: constraint,
                column: newFKColumn,
                referenced: referenced,
                referencedColumn: refColumn
            )
            newFKName = ""
            newFKColumn = ""
            newFKRefTable = ""
            newFKRefColumn = ""
            foreignKeys = try await manager.foreignKeys(of: table, on: connectionID)
        } catch {
            errorMessage = (error as? DatabaseError)?.userMessage ?? String(describing: error)
        }
    }

    private func dropForeignKey(_ fk: ForeignKeyRef) async {
        guard let table = existingTable else { return }
        errorMessage = nil
        do {
            try await manager.dropForeignKey(named: fk.constraintName, from: table, on: connectionID)
            foreignKeys = try await manager.foreignKeys(of: table, on: connectionID)
        } catch {
            errorMessage = (error as? DatabaseError)?.userMessage ?? String(describing: error)
        }
    }

    // MARK: - Save

    private func save() {
        errorMessage = nil
        let names = cleanedColumns.map(\.name)
        if Set(names).count != names.count {
            errorMessage = "Two columns share the same name."
            return
        }
        if mode == .edit {
            let dropped = originalColumns
                .filter { original in !cleanedColumns.contains { $0.id == original.id } }
                .map(\.name)
            if !dropped.isEmpty {
                pendingDropColumns = dropped
                return
            }
        }
        performSave()
    }

    private func performSave() {
        saving = true
        errorMessage = nil
        Task {
            do {
                let resultRef: TableRef
                switch mode {
                case .create:
                    let table = TableRef(database: database, schema: schema, name: trimmedName)
                    try await manager.createTable(table, on: connectionID, columns: cleanedColumns)
                    resultRef = table
                case .edit:
                    resultRef = try await applyEdits()
                }
                onSaved(resultRef)
            } catch {
                errorMessage = (error as? DatabaseError)?.userMessage ?? String(describing: error)
                if mode == .edit { await loadExisting() }
            }
            saving = false
        }
    }

    private var previewStatements: [String] {
        let previewMode: StructureDDLPreview.Mode = mode == .create ? .create : .edit
        return StructureDDLPreview.statements(
            mode: previewMode,
            dialect: dialect,
            database: database,
            schema: schema,
            tableName: trimmedName,
            originalName: originalName,
            existingTable: existingTable,
            columns: columns,
            originalColumns: originalColumns
        )
    }

    private var cleanedColumns: [ColumnDefinition] {
        namedColumns.map { col in
            var copy = col
            copy.name = col.name.trimmingCharacters(in: .whitespaces)
            copy.type = col.type.trimmingCharacters(in: .whitespaces)
            return copy
        }
    }

    private func applyEdits() async throws -> TableRef {
        guard let table = existingTable else { throw DatabaseError.driver("Missing table.") }
        let edited = cleanedColumns
        for original in originalColumns where !edited.contains(where: { $0.id == original.id }) {
            try await manager.dropColumn(original.name, from: table, on: connectionID)
        }
        for column in edited where !originalColumns.contains(where: { $0.id == column.id }) {
            try await manager.addColumn(to: table, on: connectionID, column: column)
        }
        for column in edited {
            if let original = originalColumns.first(where: { $0.id == column.id }), original.name != column.name {
                try await manager.renameColumn(original.name, to: column.name, in: table, on: connectionID)
            }
        }
        if trimmedName != originalName {
            try await manager.renameTable(table, on: connectionID, to: trimmedName)
            return TableRef(database: table.database, schema: table.schema, name: trimmedName, kind: table.kind)
        }
        return table
    }
}

// MARK: - DDL preview sheet

private struct DDLPreviewSheet: View {
    let statements: [String]
    @Environment(\.dismiss) private var dismiss

    private var sqlText: String {
        statements.map { $0.hasSuffix(";") ? $0 : $0 + ";" }.joined(separator: "\n\n")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("DDL Preview")
                    .font(.headline)
                Spacer()
                Text("\(statements.count) statement\(statements.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
            ScrollView {
                Text(sqlText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
            }
            .padding()
        }
        .frame(width: 560, height: 360)
    }
}
