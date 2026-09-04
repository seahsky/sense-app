// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SenseUI",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SenseUI",
            targets: ["SenseUI"]
        )
    ],
    targets: [
        .target(
            name: "SenseUI",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
