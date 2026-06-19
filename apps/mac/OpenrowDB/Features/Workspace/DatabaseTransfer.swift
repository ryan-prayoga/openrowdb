// DatabaseTransfer.swift
import AppKit
import OpenrowDBCore
import SwiftUI
import UniformTypeIdentifiers

/// Header menu for moving a whole database in and out as a SQL file: export a
/// logical dump (schema + data, or schema only) and import/run a `.sql` file.
struct DatabaseTransferMenu: View {
    @Environment(ConnectionManager.self) private var manager
    let connectionID: UUID
    let dialect: SQLDialect
    let databaseName: String

    @State private var showSheet = false
    @State private var title = ""
    @State private var running = false
    @State private var progress = ""
    @State private var log: [String] = []
    @State private var summary: String?
    @State private var isError = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        Menu {
            Button("Export Database…") { exportDatabase(includeData: true) }
            Button("Export Schema Only…") { exportDatabase(includeData: false) }
            Divider()
            Button("Import SQL File…") { importSQL() }
        } label: {
            Label("Transfer", systemImage: "arrow.up.arrow.down.square")
        }
        .help("Export or import this database as SQL")
        .sheet(isPresented: $showSheet) {
            TransferProgressSheet(
                title: title,
                running: running,
                progress: progress,
                log: log,
                summary: summary,
                isError: isError,
                onCancel: { task?.cancel() },
                onDone: { showSheet = false }
            )
        }
    }

    // MARK: - Export

    private func exportDatabase(includeData: Bool) {
        let suggested = (databaseName.isEmpty ? "database" : databaseName) + (includeData ? "" : "-schema") + ".sql"
        guard let url = SQLFileIO.chooseSaveURL(suggested: suggested) else { return }
        beginSheet(includeData ? "Exporting \(databaseName)" : "Exporting schema")
        task = Task {
            do {
                let tables = try await manager.tables(on: connectionID).filter { $0.kind == .table }
                guard !tables.isEmpty else { return finish("No tables to export.", error: false) }
                let options = SQLDumpBuilder.Options(dropIfExists: true, createTable: true, includeData: includeData)
                let sql = try await DatabaseExporter.buildDump(
                    tables: tables,
                    manager: manager,
                    connectionID: connectionID,
                    dialect: dialect,
                    options: options
                ) { progress = $0 }
                try SQLFileIO.write(sql, to: url)
                let count = tables.count
                finish("Exported \(count) table\(count == 1 ? "" : "s") to \(url.lastPathComponent).", error: false)
            } catch is CancellationError {
                finish("Export cancelled.", error: true)
            } catch {
                finish(Self.message(error), error: true)
            }
        }
    }

    // MARK: - Import

    private func importSQL() {
        guard let url = SQLFileIO.chooseOpenURL() else { return }
        beginSheet("Importing \(url.lastPathComponent)")
        task = Task {
            let text: String
            do {
                text = try String(contentsOf: url, encoding: .utf8)
            } catch {
                return finish("Couldn't read \(url.lastPathComponent): \(Self.message(error))", error: true)
            }
            let statements = SQLStatementSplitter.split(text)
            guard !statements.isEmpty else { return finish("No statements found in the file.", error: false) }

            var succeeded = 0
            var failed = 0
            for (index, statement) in statements.enumerated() {
                if Task.isCancelled { break }
                progress = "\(index + 1)/\(statements.count)"
                do {
                    _ = try await manager.run(statement, on: connectionID)
                    succeeded += 1
                } catch {
                    failed += 1
                    log.append("✗ \(Self.shorten(statement)) — \(Self.message(error))")
                }
            }
            let cancelled = Task.isCancelled
            finish(
                "\(succeeded) statement\(succeeded == 1 ? "" : "s") succeeded, \(failed) failed\(cancelled ? " (cancelled)" : "").",
                error: failed > 0
            )
        }
    }

    // MARK: - Sheet state

    private func beginSheet(_ title: String) {
        self.title = title
        running = true
        progress = ""
        log = []
        summary = nil
        isError = false
        showSheet = true
    }

    private func finish(_ summary: String, error: Bool) {
        self.summary = summary
        isError = error
        running = false
    }

    private static func shorten(_ sql: String) -> String {
        let oneLine = sql.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 80 ? String(oneLine.prefix(80)) + "…" : oneLine
    }

    private static func message(_ error: Error) -> String {
        (error as? DatabaseError)?.userMessage ?? String(describing: error)
    }
}

// MARK: - Exporter

/// Builds a SQL dump for the given tables by introspecting each and selecting
/// all of its rows. `@MainActor` because it drives the main-actor `ConnectionManager`.
@MainActor
enum DatabaseExporter {
    static func buildDump(
        tables: [TableRef],
        manager: ConnectionManager,
        connectionID: UUID,
        dialect: SQLDialect,
        options: SQLDumpBuilder.Options,
        progress: (String) -> Void = { _ in }
    ) async throws -> String {
        var dumps: [SQLDumpBuilder.TableDump] = []
        for (index, table) in tables.enumerated() {
            try Task.checkCancellation()
            progress("\(index + 1)/\(tables.count): \(table.name)")
            let columns = try await manager.columnDefinitions(of: table, on: connectionID)
            let data: QueryResult = options.includeData
                ? try await manager.run("SELECT * FROM \(dialect.qualifiedName(table))", on: connectionID, database: table.database)
                : .empty
            dumps.append(SQLDumpBuilder.TableDump(table: table, columns: columns, data: data))
        }
        return SQLDumpBuilder.build(dumps, dialect: dialect, options: options)
    }
}

// MARK: - File IO

enum SQLFileIO {
    static var sqlType: UTType { UTType(filenameExtension: "sql") ?? .plainText }

    @MainActor
    static func chooseSaveURL(suggested: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [sqlType]
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func chooseOpenURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [sqlType, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url, options: .atomic)
    }
}

// MARK: - Progress sheet

private struct TransferProgressSheet: View {
    let title: String
    let running: Bool
    let progress: String
    let log: [String]
    let summary: String?
    let isError: Bool
    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if running {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(progress.isEmpty ? "Working…" : progress)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } else if let summary {
                    Label(summary, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? .red : .green)
                }

                if !log.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxWidth: .infinity)
                    .background(.quaternary, in: .rect(cornerRadius: 6))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            HStack {
                Spacer()
                if running {
                    Button("Cancel", role: .cancel) { onCancel() }
                        .buttonStyle(.glass)
                } else {
                    Button("Done") { onDone() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 360)
    }
}
