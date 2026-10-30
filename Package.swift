// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Cooldown",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Cooldown", targets: ["Cooldown"]),
        .library(name: "CooldownCore", targets: ["CooldownCore"])
    ],
    targets: [
        // Pure logic: what to clean, how to measure it, how to clean it safely.
        // Foundation only, no UI, so it is unit-testable on its own.
        .target(
            name: "CooldownCore",
            path: "Sources/CooldownCore"
        ),
        // The menu bar app (SwiftUI). Thin layer over CooldownCore.
        .executableTarget(
            name: "Cooldown",
            dependencies: ["CooldownCore"],
            path: "Sources/Cooldown"
        ),
        .testTarget(
            name: "CooldownCoreTests",
            dependencies: ["CooldownCore"],
            path: "Tests/CooldownCoreTests"
        )
    ]
)
