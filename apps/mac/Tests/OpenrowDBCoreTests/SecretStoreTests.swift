// SecretStoreTests.swift
import XCTest
@testable import OpenrowDBCore

final class SecretStoreTests: XCTestCase {
    func testInMemorySetGet() throws {
        let store = InMemorySecretStore()
        try store.set("hunter2", for: "key1")
        XCTAssertEqual(try store.get("key1"), "hunter2")
    }

    func testInMemoryMissingReturnsNil() throws {
        let store = InMemorySecretStore()
        XCTAssertNil(try store.get("absent"))
    }

    func testInMemoryOverwrite() throws {
        let store = InMemorySecretStore()
        try store.set("old", for: "k")
        try store.set("new", for: "k")
        XCTAssertEqual(try store.get("k"), "new")
    }

    func testInMemoryRemove() throws {
        let store = InMemorySecretStore()
        try store.set("v", for: "k")
        try store.remove("k")
        XCTAssertNil(try store.get("k"))
    }
}
