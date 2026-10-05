// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screener",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ScreenerCore", targets: ["ScreenerCore"]),
        .library(name: "ScreenerKit", targets: ["ScreenerKit"]),
    ],
    targets: [
        .target(name: "ScreenerCore"),
        .target(name: "ScreenerKit", dependencies: ["ScreenerCore"]),
        .testTarget(name: "ScreenerCoreTests", dependencies: ["ScreenerCore"]),
        .testTarget(name: "ScreenerKitTests", dependencies: ["ScreenerKit", "ScreenerCore"]),
    ]
)
