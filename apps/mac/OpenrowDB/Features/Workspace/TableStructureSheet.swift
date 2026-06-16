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
