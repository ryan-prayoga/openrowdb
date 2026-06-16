// RefreshCoordinator.swift
import Foundation

/// Broadcasts a per-connection refresh signal (⌘R). Subscribers bump their
/// own serial and reload whatever surface they own — sidebar tree, table page,
/// schema catalog — without a central refresh orchestrator.
@Observable
final class RefreshCoordinator {
    private var signals: [UUID: Int] = [:]

    /// Monotonic counter for `connectionID`. Observed via `.onChange` in views.
    func signal(for connectionID: UUID) -> Int {
        signals[connectionID] ?? 0
    }

    /// Request a refresh for the given connection. No-op callers should guard
    /// on connection status before calling.
    func refresh(connectionID: UUID) {
        signals[connectionID, default: 0] += 1
    }
}