// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CindyKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "CindyKit",
            targets: ["CindyKit"]
        )
    ],
    targets: [
        .target(
            name: "CindyKit"
        ),
        .testTarget(
            name: "CindyKitTests",
            dependencies: ["CindyKit"]
        )
    ]
)
