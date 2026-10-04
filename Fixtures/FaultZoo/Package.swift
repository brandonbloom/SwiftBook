// swift-tools-version: 6.2

import PackageDescription

// Previews that misbehave: one crashes, one hangs, one is slow. The viewer's renderer supervision
// tests run against it. Nothing else renders it, since it would crash or hang them.
let package = Package(
    name: "FaultZoo",
    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "FaultZoo", targets: ["FaultZoo"])
    ],
    dependencies: [
        .package(name: "SwiftBook", path: "../..")
    ],
    targets: [
        .target(name: "FaultZoo")
    ]
)
