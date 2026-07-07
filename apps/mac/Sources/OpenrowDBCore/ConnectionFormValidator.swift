// ConnectionFormValidator.swift
import Foundation

/// Field-level validation for the connection sheet.
public struct ConnectionFormValidator {
  public struct FieldErrors: Sendable, Equatable {
    public var name: String?
    public var host: String?
    public var port: String?
    public var user: String?
    public var sshHost: String?
    public var sshPort: String?
    public var sshUser: String?

    public init(
      name: String? = nil,
      host: String? = nil,
      port: String? = nil,
      user: String? = nil,
      sshHost: String? = nil,
      sshPort: String? = nil,
      sshUser: String? = nil
    ) {
      self.name = name
      self.host = host
      self.port = port
      self.user = user
      self.sshHost = sshHost
      self.sshPort = sshPort
      self.sshUser = sshUser
    }

    public var hasAny: Bool {
      name != nil || host != nil || port != nil || user != nil
        || sshHost != nil || sshPort != nil || sshUser != nil
    }
  }

  public static func validate(
    name: String,
    host: String,
    port: Int,
    user: String,
    sshEnabled: Bool,
    sshHost: String,
    sshPort: Int,
    sshUser: String
  ) -> FieldErrors {
    var errors = FieldErrors()
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.name = "Name is required."
    }
    if host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.host = "Host is required."
    }
    if port < 1 || port > 65535 {
      errors.port = "Port must be between 1 and 65535."
    }
    if user.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      errors.user = "User is required."
    }
    if sshEnabled {
      if sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errors.sshHost = "SSH host is required."
      }
      if sshPort < 1 || sshPort > 65535 {
        errors.sshPort = "SSH port must be between 1 and 65535."
      }
      if sshUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errors.sshUser = "SSH user is required."
      }
    }
    return errors
  }
}