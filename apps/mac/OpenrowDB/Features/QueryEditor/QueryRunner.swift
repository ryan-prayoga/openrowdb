// QueryRunner.swift
import Foundation
import Observation
import OpenrowDBCore

/// View model that drives one query tab: holds the editor's text, runs SQL via
/// the shared `ConnectionManager`, splits multi-statement input, records each
/// run to `QueryHistoryStore`, and exposes per-statement results + status.
@MainActor
@Observable
final class QueryRunner {
    /// Result of one statement inside a multi-statement run.
    struct StatementOutcome: Identifiable, Equatable {
        let id = UUID()
        let sql: String
        let durationMs: Int
        let result: QueryResult?
        let error: String?
        /// 1-indexed character offset within `sql` where the server pinpointed
        /// the error. Postgres only; nil for MySQL or non-positional errors.
        let errorPosition: Int?

        var didFail: Bool { error != nil }
    }

    enum State: Equatable {
        case idle
        case running(progress: String)
        case finished
    }

    let connectionID: UUID
    let tabID: UUID

    var sql: String = ""
    private(set) var state: State = .idle
    private(set) var outcomes: [StatementOutcome] = []
    /// Target database for this tab's queries + autocomplete. `nil` = the
    /// connection's default database. Set via `useDatabase` so the schema
    /// catalog reloads for the new database.
    private(set) var database: String?
    /// The SQL text of the most recent run, used to flag a tab as having
    /// un-run edits (the dirty dot in the tab strip).
    private(set) var lastRunSQL: String?
    /// True when the editor holds non-empty SQL that differs from the last run.
    var isDirty: Bool {
        !sql.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sql != lastRunSQL
    }
    /// True when the last run produced at least one outcome.
    var hasResults: Bool { !outcomes.isEmpty }

    private var dialect: SQLDialect {
        manager.connections.first { $0.id == connectionID }?.driver.dialect ?? .postgres
    }

    let catalog: SchemaCatalog

    @ObservationIgnored
    private let manager: ConnectionManager
    @ObservationIgnored
    private let history: QueryHistoryStore
    @ObservationIgnored
    private var currentTask: Task<Void, Never>?

    init(connectionID: UUID, tabID: UUID, manager: ConnectionManager, history: QueryHistoryStore) {
        self.connectionID = connectionID
        self.tabID = tabID
        self.manager = manager
        self.history = history
        self.catalog = SchemaCatalog(connectionID: connectionID, manager: manager)
    }

    /// Kick off a run. Cancels any in-flight run for this tab first so spamming
    /// ⌘Return doesn't pile up overlapping queries against the same connection.
    /// Run the editor's full SQL, or `override` (a selection or the statement
    /// under the caret) when provided. Only a full run clears the dirty flag —
    /// running a fragment leaves the tab marked as having un-run content.
    func run(_ override: String? = nil) {
        currentTask?.cancel()
        let source = override ?? sql
        if override == nil { lastRunSQL = sql }
        let statements = SQLStatementSplitter.split(source)
        guard !statements.isEmpty else {
            outcomes = []
            state = .finished
            return
        }

        outcomes = []
        state = .running(progress: "0/\(statements.count)")
        let captured = statements
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.executeAll(captured)
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        if case .running = state { state = .finished }
    }

    /// Point this tab at a different database. Reloads the completion catalog so
    /// table/column suggestions reflect the chosen database, not the
    /// connection's default.
    func useDatabase(_ db: String?) {
        guard db != database else { return }
        database = db
        catalog.database = db
        Task { await catalog.refresh() }
    }

    private func executeAll(_ statements: [String]) async {
        for (index, statement) in statements.enumerated() {
            if Task.isCancelled { break }
            state = .running(progress: "\(index)/\(statements.count)")
            let outcome = await execute(statement)
            outcomes.append(outcome)
            await record(original: statement, outcome: outcome)
        }
        state = .finished
    }

    private func execute(_ sql: String) async -> StatementOutcome {
        let start = ContinuousClock.now
        do {
            let result = try await manager.run(sql, on: connectionID, database: database)
            let elapsed = elapsedMs(since: start)
            return StatementOutcome(
                sql: sql,
                durationMs: elapsed,
                result: result,
                error: nil,
                errorPosition: nil
            )
        } catch {
            let elapsed = elapsedMs(since: start)
            let dbError = error as? DatabaseError
            let message = dbError?.userMessage ?? String(describing: error)
            var position: Int?
            if case let .query(_, _, _, p) = dbError { position = p }
            return StatementOutcome(
                sql: sql,
                durationMs: elapsed,
                result: nil,
                error: message,
                errorPosition: position
            )
        }
    }

    private func record(original sql: String, outcome: StatementOutcome) async {
        let entry = HistoryEntry(
            connectionID: connectionID,
            sql: sql,
            executedAt: Date(),
            durationMs: outcome.durationMs,
            rowsAffected: outcome.result?.rowsAffected,
            error: outcome.error
        )
        // History writes never propagate errors to the user — a failing SQLite
        // shouldn't surface a second "query failed" toast on top of a real DB error.
        try? await history.record(entry)
    }

    private func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        let components = elapsed.components
        let nanos = Double(components.attoseconds) / 1_000_000_000
        return Int(Double(components.seconds) * 1_000 + nanos / 1_000_000)
    }
}
