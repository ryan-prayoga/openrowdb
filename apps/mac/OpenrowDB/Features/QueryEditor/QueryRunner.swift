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
    /// True when the last run produced at least one outcome.
    var hasResults: Bool { !outcomes.isEmpty }

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
    func run() {
        currentTask?.cancel()
        let statements = SQLStatementSplitter.split(sql)
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

    private func executeAll(_ statements: [String]) async {
        for (index, statement) in statements.enumerated() {
            if Task.isCancelled { break }
            state = .running(progress: "\(index)/\(statements.count)")
            let outcome = await execute(statement)
            outcomes.append(outcome)
            await record(outcome)
        }
        state = .finished
    }

    private func execute(_ sql: String) async -> StatementOutcome {
        let start = ContinuousClock.now
        do {
            let result = try await manager.run(sql, on: connectionID)
            let elapsed = elapsedMs(since: start)
            return StatementOutcome(sql: sql, durationMs: elapsed, result: result, error: nil)
        } catch {
            let elapsed = elapsedMs(since: start)
            let message = (error as? DatabaseError)?.userMessage ?? String(describing: error)
            return StatementOutcome(sql: sql, durationMs: elapsed, result: nil, error: message)
        }
    }

    private func record(_ outcome: StatementOutcome) async {
        let entry = HistoryEntry(
            connectionID: connectionID,
            sql: outcome.sql,
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
