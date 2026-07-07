// EditorCommandCenter.swift
import SwiftUI

/// Routes app-menu Edit commands to whichever query editor tab is active.
@MainActor
@Observable
final class EditorCommandCenter {
  static let shared = EditorCommandCenter()

  private(set) weak var activeAccess: EditorAccess?

  private init() {}

  func register(_ access: EditorAccess) {
    activeAccess = access
  }

  func unregister(_ access: EditorAccess) {
    if activeAccess === access {
      activeAccess = nil
    }
  }

  func find() {
    activeAccess?.presentFindInterface()
  }

  func undo() {
    activeAccess?.undo()
  }

  func redo() {
    activeAccess?.redo()
  }
}