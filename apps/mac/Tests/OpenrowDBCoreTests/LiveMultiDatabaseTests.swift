// LiveMultiDatabaseTests.swift
//
// End-to-end checks for "all databases in one connection" against REAL servers.
// Skipped unless OPENROW_LIVE_DB=1, so CI (no DB) stays green. Run locally with:
//   OPENROW_LIVE_DB=1 swift test --filter LiveMultiDatabaseTests
//
// Expects the demo data seeded by the setup step:
//   Postgres @127.0.0.1:5432 user `ryanprayoga` (trust): openrow_demo_shop
//     (public.users/orders/order_totals + analytics.events), openrow_demo_blog
//     (public.posts/comments)
//   MySQL    @127.0.0.1:3306 user root/demopass: shop_demo (users/orders/big_orders),
//     analytics_demo (events)
import XCTest
@testable import OpenrowDBCore

@MainActor
final class LiveMultiDatabaseTests: XCTestCase {
    private func makeManager() throws -> ConnectionManager {
        let store = try ConnectionStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("live-\(UUID().uuidString).json")
        )
        return ConnectionManager(store: store, secrets: InMemorySecretStore())
    }

    private func names(_ tables: [TableRef]) -> Set<String> { Set(tables.map(\.name)) }

    func testPostgresOneConnectionSeesEveryDatabase() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENROW_LIVE_DB"] == "1")

        let manager = try makeManager()
        let conn = Connection(
            name: "PG demo", driver: .postgres, host: "127.0.0.1", port: 5432,
            user: "ryanprayoga", passwordKeychainKey: "pg", database: "openrow_demo_shop",
            sslMode: .disable
        )
        try manager.add(conn, password: "")
        await manager.connect(conn.id)
        XCTAssertEqual(manager.status[conn.id], .connected)

        // All databases on the server, from the one connection.
        let dbs = try await manager.databases(on: conn.id)
        XCTAssertTrue(dbs.contains("openrow_demo_shop"), "got \(dbs)")
        XCTAssertTrue(dbs.contains("openrow_demo_blog"), "got \(dbs)")

        // Default database: lists every schema (public + analytics).
        let shop = try await manager.tables(on: conn.id, database: "openrow_demo_shop")
        XCTAssertTrue(names(shop).isSuperset(of: ["users", "orders", "order_totals", "events"]), "got \(names(shop))")
        XCTAssertTrue(shop.contains { $0.schema == "analytics" && $0.name == "events" })
        XCTAssertTrue(shop.contains { $0.name == "order_totals" && $0.kind == .view })

        // NON-default database: forces a second pooled Postgres client to open.
        let blog = try await manager.tables(on: conn.id, database: "openrow_demo_blog")
        XCTAssertEqual(names(blog), ["posts", "comments"], "got \(names(blog))")

        // And we can actually read rows across that second client.
        if let posts = blog.first(where: { $0.name == "posts" }) {
            let rows = try await manager.fetchRows(posts, on: conn.id, limit: 10, offset: 0)
            XCTAssertEqual(rows.rows.count, 2)
        } else {
            XCTFail("posts table missing")
        }

        await manager.disconnect(conn.id)
    }

    func testMySQLOneConnectionSeesEveryDatabase() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OPENROW_LIVE_DB"] == "1")

        let manager = try makeManager()
        let conn = Connection(
            name: "MySQL demo", driver: .mysql, host: "127.0.0.1", port: 3306,
            user: "root", passwordKeychainKey: "my", database: "shop_demo",
            sslMode: .disable
        )
        try manager.add(conn, password: "demopass")
        await manager.connect(conn.id)
        XCTAssertEqual(manager.status[conn.id], .connected)

        let dbs = try await manager.databases(on: conn.id)
        XCTAssertTrue(dbs.contains("shop_demo"), "got \(dbs)")
        XCTAssertTrue(dbs.contains("analytics_demo"), "got \(dbs)")
        XCTAssertFalse(dbs.contains("mysql"), "system schemas should be hidden: \(dbs)")

        let shop = try await manager.tables(on: conn.id, database: "shop_demo")
        XCTAssertTrue(names(shop).isSuperset(of: ["users", "orders", "big_orders"]), "got \(names(shop))")

        // Different database, SAME underlying connection (no reconnect).
        let analytics = try await manager.tables(on: conn.id, database: "analytics_demo")
        XCTAssertEqual(names(analytics), ["events"], "got \(names(analytics))")
        if let events = analytics.first {
            let rows = try await manager.fetchRows(events, on: conn.id, limit: 10, offset: 0)
            XCTAssertEqual(rows.rows.count, 4)
        }

        await manager.disconnect(conn.id)
    }
}
