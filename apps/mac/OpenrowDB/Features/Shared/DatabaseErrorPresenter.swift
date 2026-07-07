// DatabaseErrorPresenter.swift
import Foundation
import OpenrowDBCore

/// Maps driver/store errors to user-facing copy for alerts and placeholders.
enum DatabaseErrorPresenter {
  struct Failure: Identifiable {
    let id = UUID()
    let title: String
    let message: String
  }

  static func message(for error: Error) -> String {
    if let databaseError = error as? DatabaseError {
      return databaseError.userMessage
    }
    return error.localizedDescription
  }

  static func failure(title: String, error: Error) -> Failure {
    Failure(title: title, message: message(for: error))
  }
}