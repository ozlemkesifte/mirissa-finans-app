// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MirissaKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MirissaCore", targets: ["MirissaCore"]),
        .library(name: "MirissaUI", targets: ["MirissaUI"]),
    ],
    targets: [
        .target(
            name: "MirissaCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "MirissaUI",
            dependencies: ["MirissaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MirissaPreview",
            dependencies: ["MirissaCore", "MirissaUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MirissaCoreTests",
            dependencies: ["MirissaCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
