// GlobalSearchCoordinator.swift
import Foundation
import Observation
import OpenrowDBCore

/// Routes global search (⌘K) selections back to the active window.
@MainActor
@Observable
final class GlobalSearchCoordinator {
  var isPresented = false

  var onSelectConnection: ((UUID) -> Void)?
  var onOpenTable: ((UUID, TableRef) -> Void)?
  var onLoadHistoryQuery: ((UUID, String) -> Void)?
  var onSelectTab: ((UUID, WorkspaceTab) -> Void)?

  func present() {
    isPresented = true
  }
}