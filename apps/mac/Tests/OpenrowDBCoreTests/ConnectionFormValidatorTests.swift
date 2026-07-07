// ConnectionFormValidatorTests.swift
import XCTest
@testable import OpenrowDBCore

final class ConnectionFormValidatorTests: XCTestCase {
  func testValidFormHasNoErrors() {
    let errors = ConnectionFormValidator.validate(
      name: "Local",
      host: "127.0.0.1",
      port: 5432,
      user: "postgres",
      sshEnabled: false,
      sshHost: "",
      sshPort: 22,
      sshUser: ""
    )
    XCTAssertFalse(errors.hasAny)
  }

  func testMissingHostAndInvalidPort() {
    let errors = ConnectionFormValidator.validate(
      name: "Local",
      host: " ",
      port: 0,
      user: "postgres",
      sshEnabled: false,
      sshHost: "",
      sshPort: 22,
      sshUser: ""
    )
    XCTAssertNotNil(errors.host)
    XCTAssertNotNil(errors.port)
  }

  func testSSHFieldsRequiredWhenEnabled() {
    let errors = ConnectionFormValidator.validate(
      name: "Remote",
      host: "db.example.com",
      port: 5432,
      user: "postgres",
      sshEnabled: true,
      sshHost: "",
      sshPort: 70000,
      sshUser: ""
    )
    XCTAssertNotNil(errors.sshHost)
    XCTAssertNotNil(errors.sshPort)
    XCTAssertNotNil(errors.sshUser)
  }
}