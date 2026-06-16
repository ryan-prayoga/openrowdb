// QuerySnippetStoreTests.swift
import Foundation
import Testing
@testable import OpenrowDBCore

@Suite struct QuerySnippetStoreTests {
    @Test func saveAndLoad() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try QuerySnippetStore(fileURL: url)
        let conn = UUID()
        let entry = try await store.upsert(connectionID: conn, title: "Users", sql: "SELECT * FROM users")

        let loaded = try await store.entries(forConnection: conn)
        #expect(loaded.count == 1)
        #expect(loaded[0].id == entry.id)
        #expect(loaded[0].title == "Users")
        #expect(loaded[0].sql == "SELECT * FROM users")
    }

    @Test func delete() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("snippets-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try QuerySnippetStore(fileURL: url)
        let conn = UUID()
        let entry = try await store.upsert(connectionID: conn, title: "A", sql: "SELECT 1")
        try await store.delete(id: entry.id)
        #expect(try await store.entries(forConnection: conn).isEmpty)
    }
}