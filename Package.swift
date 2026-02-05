// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Bufr",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.24.0"),
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "Bufr",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "HotKey", package: "HotKey"),
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
