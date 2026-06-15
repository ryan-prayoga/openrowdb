// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenrowDBCore",
    platforms: [
        .macOS(.v15)  // bump to v26 when SwiftPM ships macOS 26 support; v15 is the floor for now
    ],
    products: [
        .library(name: "OpenrowDBCore", targets: ["OpenrowDBCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
        .package(url: "https://github.com/vapor/mysql-nio.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "OpenrowDBCore",
            dependencies: [
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "Sources/OpenrowDBCore"
        ),
        .testTarget(
            name: "OpenrowDBCoreTests",
            dependencies: ["OpenrowDBCore"],
            path: "Tests/OpenrowDBCoreTests"
        )
    ]
)
