// WorkspaceSessionStoreTests.swift
import XCTest
@testable import OpenrowDBCore

final class WorkspaceSessionStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testRoundTrip() throws {
        let file = tempDir.appendingPathComponent("workspace.json")
        let store = try WorkspaceSessionStore(fileURL: file)
        let connectionID = UUID()
        let table = TableRef(database: "app", schema: "public", name: "users")
        let data = WorkspaceSessionData(
            tabs: [
                .query(id: UUID(), sql: "SELECT 1"),
                .table(ref: table, filterColumn: "id", filterValue: "42"),
            ],
            selectedTabKey: "table:\(table.id)"
        )

        try store.save(data, for: connectionID)
        let loaded = try XCTUnwrap(store.load(for: connectionID))
        XCTAssertEqual(loaded, data)
    }

    func testEmptyTabsRemovesSession() throws {
        let file = tempDir.appendingPathComponent("workspace.json")
        let store = try WorkspaceSessionStore(fileURL: file)
        let connectionID = UUID()
        try store.save(WorkspaceSessionData(tabs: [.query(id: UUID(), sql: "x")]), for: connectionID)
        try store.save(WorkspaceSessionData(), for: connectionID)
        XCTAssertNil(try store.load(for: connectionID))
    }
}