// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClingLite",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClingCore", targets: ["ClingCore"]),
        .executable(name: "cling", targets: ["cling"]),
    ],
    targets: [
        .target(
            name: "ClingCore",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        ),
        .executableTarget(name: "cling", dependencies: ["ClingCore"]),
        .testTarget(name: "ClingCoreTests", dependencies: ["ClingCore"]),
    ]
)
