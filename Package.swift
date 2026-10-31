// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ClawdBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClawdBar", targets: ["ClawdBar"]),
        .executable(name: "clawd-hook", targets: ["clawd-hook"]),
    ],
    targets: [
        .target(name: "ClawdCore"),
        .executableTarget(name: "clawd-hook", dependencies: ["ClawdCore"]),
        .executableTarget(name: "ClawdBar", dependencies: ["ClawdCore"]),
        .testTarget(name: "ClawdCoreTests", dependencies: ["ClawdCore"]),
    ]
)
