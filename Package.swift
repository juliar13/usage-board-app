// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageBoard",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "UsageBoard", targets: ["UsageBoard"])],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "UsageBoard", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"])
    ]
)
