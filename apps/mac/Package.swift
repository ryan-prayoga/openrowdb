// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenrowDBCore",
    platforms: [
        .macOS(.v26)  // Liquid Glass (glassEffect / .glass button style) is macOS 26 Tahoe only
    ],
    products: [
        .library(name: "OpenrowDBCore", targets: ["OpenrowDBCore"]),
        // SwiftUI app, buildable headlessly via SwiftPM for CI + fast iteration.
        // Shippable .app bundle (Info.plist, entitlements, codesign) is a Phase 5
        // Xcode-project concern; this target verifies the UI compiles against Core.
        .executable(name: "OpenrowDB", targets: ["OpenrowDB"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0"),
        // Phase 3: query history (local SQLite). GRDB picked over SQLite3 system lib for
        // its async API, type-safe row decoding, and battle-tested concurrency model.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "OpenrowDBCore",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/OpenrowDBCore"
        ),
        .executableTarget(
            name: "OpenrowDB",
            dependencies: ["OpenrowDBCore"],
            path: "OpenrowDB",
            // Resources processed by Xcode build system:
            // - Assets.xcassets  → compiled by actool (app icon, accent color)
            // - Info.plist       → embedded in .app bundle (Phase 5 / Xcode only)
            // - OpenrowDB.entitlements → referenced in Xcode signing settings (not SwiftPM)
            resources: [
                .process("Resources/Assets.xcassets"),
            ]
        ),
        .testTarget(
            name: "OpenrowDBCoreTests",
            dependencies: ["OpenrowDBCore"],
            path: "Tests/OpenrowDBCoreTests"
        )
    ]
)
