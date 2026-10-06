// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Screener",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ScreenerCore", targets: ["ScreenerCore"]),
        .library(name: "ScreenerKit", targets: ["ScreenerKit"]),
        .library(name: "ScreenerMCP", targets: ["ScreenerMCP"]),
        .executable(name: "screener-mcp", targets: ["screener-mcp"]),
        .executable(name: "screener-benchmarks", targets: ["screener-benchmarks"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    ],
    targets: [
        .target(name: "ScreenerCore"),
        .target(name: "ScreenerKit", dependencies: ["ScreenerCore"]),
        .target(name: "ScreenerMCP", dependencies: ["ScreenerCore", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "screener-mcp", dependencies: ["ScreenerMCP", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "screener-benchmarks", dependencies: ["ScreenerCore", "ScreenerMCP"]),
        .testTarget(name: "ScreenerCoreTests", dependencies: ["ScreenerCore"]),
        .testTarget(name: "ScreenerKitTests", dependencies: ["ScreenerKit", "ScreenerCore"]),
        .testTarget(name: "ScreenerMCPTests", dependencies: ["ScreenerMCP", "ScreenerCore", .product(name: "MCP", package: "swift-sdk")]),
    ]
)
