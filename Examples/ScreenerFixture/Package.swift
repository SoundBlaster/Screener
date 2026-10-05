// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenerFixture",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(
            name: "ScreenerFixture",
            dependencies: [.product(name: "ScreenerKit", package: "Screener")]
        )
    ]
)
