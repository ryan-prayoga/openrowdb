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
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.27.0")
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
                .product(name: "NIOSSL", package: "swift-nio-ssl")
            ],
            path: "Sources/OpenrowDBCore"
        ),
        .executableTarget(
            name: "OpenrowDB",
            dependencies: ["OpenrowDBCore"],
            path: "OpenrowDB"
        ),
        .testTarget(
            name: "OpenrowDBCoreTests",
            dependencies: ["OpenrowDBCore"],
            path: "Tests/OpenrowDBCoreTests"
        )
    ]
)
