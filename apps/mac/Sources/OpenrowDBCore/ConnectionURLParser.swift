// ConnectionURLParser.swift
import Foundation

/// Parses `postgres://` / `postgresql://` / `mysql://` URLs into connection fields.
public enum ConnectionURLParser {
  public struct Parsed: Equatable, Sendable {
    public var driver: Connection.Driver
    public var host: String
    public var port: Int
    public var user: String
    public var password: String
    public var database: String
    public var sslMode: Connection.SSLMode

    public init(
      driver: Connection.Driver,
      host: String,
      port: Int,
      user: String,
      password: String = "",
      database: String = "",
      sslMode: Connection.SSLMode = .prefer
    ) {
      self.driver = driver
      self.host = host
      self.port = port
      self.user = user
      self.password = password
      self.database = database
      self.sslMode = sslMode
    }
  }

  public enum ParseError: Error, Sendable, Equatable {
    case empty
    case invalidScheme(String)
    case missingHost
    case invalidURL
  }

  public static func parse(_ raw: String) throws -> Parsed {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ParseError.empty }

    guard let components = URLComponents(string: trimmed) else {
      throw ParseError.invalidURL
    }

    let scheme = (components.scheme ?? "").lowercased()
    let driver: Connection.Driver
    switch scheme {
    case "postgres", "postgresql":
      driver = .postgres
    case "mysql":
      driver = .mysql
    default:
      throw ParseError.invalidScheme(scheme.isEmpty ? "(none)" : scheme)
    }

    guard let host = components.host, !host.isEmpty else {
      throw ParseError.missingHost
    }

    let port = components.port ?? driver.defaultPort
    let user = components.user ?? ""
    let password = components.password ?? ""
    let database = String(components.path.dropFirst()) // strip leading /

    let sslMode: Connection.SSLMode
    if let ssl = components.queryItems?.first(where: { $0.name == "sslmode" })?.value?.lowercased() {
      switch ssl {
      case "disable", "disabled": sslMode = .disable
      case "require", "required": sslMode = .require
      default: sslMode = .prefer
      }
    } else if scheme == "postgresql" || scheme == "postgres" {
      sslMode = components.scheme == "postgresql" ? .prefer : .prefer
    } else {
      sslMode = .prefer
    }

    return Parsed(
      driver: driver,
      host: host,
      port: port,
      user: user,
      password: password,
      database: database,
      sslMode: sslMode
    )
  }
}