// ExportButton.swift
import AppKit
import OpenrowDBCore
import SwiftUI
import UniformTypeIdentifiers

/// Toolbar menu for exporting / copying the first successful result of a run.
/// Disabled when there's no result to export. Multi-statement runs export only
/// the first non-error result with column data; this matches what users
/// typically want and keeps the UX one-click.
struct ExportButton: View {
    let outcomes: [QueryRunner.StatementOutcome]

    @State private var lastError: String?
    @State private var showError = false

    private var exportable: QueryResult? {
        outcomes.compactMap(\.result).first(where: { !$0.columns.isEmpty })
    }

    var body: some View {
        Menu {
            Button("Export as CSV…") { exportCSV() }
            Button("Export as JSON…") { exportJSON() }
            Divider()
            Button("Copy as CSV") { copyCSV() }
            Button("Copy as JSON") { copyJSON() }
        } label: {
            Image(systemName: "square.and.arrow.up").frame(width: 16, height: 16)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .fixedSize()
        .disabled(exportable == nil)
        .help(exportable == nil ? "No result to export" : "Export or copy the first result")
        .accessibilityLabel("Export")
        .alert("Export failed", isPresented: $showError, presenting: lastError) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Actions

    private func exportCSV() {
        guard let result = exportable else { return }
        save(data: Data(ResultExporter.exportCSV(result).utf8), suggested: "results.csv", type: .commaSeparatedText)
    }

    private func exportJSON() {
        guard let result = exportable else { return }
        do {
            let data = try ResultExporter.exportJSON(result)
            save(data: data, suggested: "results.json", type: .json)
        } catch {
            lastError = String(describing: error)
            showError = true
        }
    }

    private func copyCSV() {
        guard let result = exportable else { return }
        copy(string: ResultExporter.exportCSV(result))
    }

    private func copyJSON() {
        guard let result = exportable else { return }
        do {
            let data = try ResultExporter.exportJSON(result)
            let string = String(decoding: data, as: UTF8.self)
            copy(string: string)
        } catch {
            lastError = String(describing: error)
            showError = true
        }
    }

    // MARK: - Helpers

    private func save(data: Data, suggested: String, type: UTType) {
        // NSSavePanel runs synchronously on the main thread; SwiftUI's
        // .fileExporter would also work but requires an Identifiable Document
        // wrapper for binary payloads, which is overkill here.
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            lastError = "Could not write \(url.lastPathComponent): \(error.localizedDescription)"
            showError = true
        }
    }

    private func copy(string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
