// ConnectionFormPreset.swift
import Foundation

/// Pre-filled values for the new-connection sheet (e.g. onboarding sample).
public struct ConnectionFormPreset: Sendable, Equatable {
  public var name: String
  public var driver: Connection.Driver
  public var host: String
  public var port: Int
  public var user: String
  public var database: String
  public var sslMode: Connection.SSLMode
  public var isReadOnly: Bool

  public init(
    name: String,
    driver: Connection.Driver,
    host: String,
    port: Int,
    user: String,
    database: String,
    sslMode: Connection.SSLMode = .prefer,
    isReadOnly: Bool = false
  ) {
    self.name = name
    self.driver = driver
    self.host = host
    self.port = port
    self.user = user
    self.database = database
    self.sslMode = sslMode
    self.isReadOnly = isReadOnly
  }

  public static let localPostgres = ConnectionFormPreset(
    name: "Local Postgres",
    driver: .postgres,
    host: "127.0.0.1",
    port: Connection.Driver.postgres.defaultPort,
    user: "postgres",
    database: "postgres"
  )

  public static let localMySQL = ConnectionFormPreset(
    name: "Local MySQL",
    driver: .mysql,
    host: "127.0.0.1",
    port: Connection.Driver.mysql.defaultPort,
    user: "root",
    database: "mysql"
  )
}