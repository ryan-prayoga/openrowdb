// WindowCommandRouter.swift
import Foundation
import OpenrowDBCore

/// Routes app-menu commands to whichever window is currently key.
@MainActor
final class WindowCommandRouter {
  static let shared = WindowCommandRouter()

  private struct Handlers {
    let presentNewConnection: () -> Void
    let presentNewConnectionPreset: (ConnectionFormPreset) -> Void
    let presentSearch: () -> Void
    let presentShortcuts: () -> Void
  }

  private var handlers: [UUID: Handlers] = [:]
  private var keyToken: UUID?

  private init() {}

  func register(
    token: UUID,
    presentNewConnection: @escaping () -> Void,
    presentNewConnectionPreset: @escaping (ConnectionFormPreset) -> Void,
    presentSearch: @escaping () -> Void,
    presentShortcuts: @escaping () -> Void
  ) {
    handlers[token] = Handlers(
      presentNewConnection: presentNewConnection,
      presentNewConnectionPreset: presentNewConnectionPreset,
      presentSearch: presentSearch,
      presentShortcuts: presentShortcuts
    )
    keyToken = token
  }

  func becomeKey(token: UUID) {
    guard handlers[token] != nil else { return }
    keyToken = token
  }

  func unregister(token: UUID) {
    handlers.removeValue(forKey: token)
    if keyToken == token {
      keyToken = handlers.keys.first
    }
  }

  func presentNewConnection() {
    keyHandlers?.presentNewConnection()
  }

  func presentNewConnection(preset: ConnectionFormPreset) {
    keyHandlers?.presentNewConnectionPreset(preset)
  }

  func presentSearch() {
    keyHandlers?.presentSearch()
  }

  func presentShortcuts() {
    keyHandlers?.presentShortcuts()
  }

  private var keyHandlers: Handlers? {
    keyToken.flatMap { handlers[$0] }
  }
}