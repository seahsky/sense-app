// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SenseKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "SenseKit",
            targets: ["SenseKit"]
        )
    ],
    targets: [
        .target(
            name: "SenseKit"
        ),
        .testTarget(
            name: "SenseKitTests",
            dependencies: ["SenseKit"]
        )
    ]
)
