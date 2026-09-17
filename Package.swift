// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FaceMac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FaceMacCore", targets: ["FaceMacCore"]),
        .executable(name: "facemac-demo", targets: ["FaceMacDemo"]),
    ],
    targets: [
        .target(
            name: "FaceMacCore",
            path: "Sources/FaceMacCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "FaceMacDemo",
            dependencies: ["FaceMacCore"],
            path: "Sources/FaceMacDemo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "FaceMacCoreTests",
            dependencies: ["FaceMacCore"],
            path: "Tests/FaceMacCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
