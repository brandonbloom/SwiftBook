// swift-tools-version: 6.2

import PackageDescription

// A fixture covering every preview form and the content that tends to render wrong. SwiftBook's
// discovery, adapter, and renderers test against it, and it's the canary for Xcode changes. Its
// tests consume SwiftBook the way a real package does.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "PreviewZoo",
    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "PreviewZoo", targets: ["PreviewZoo"])
    ],
    dependencies: [
        .package(name: "SwiftBook", path: "../..")
    ],
    targets: [
        .target(name: "PreviewZoo", swiftSettings: strict),
        .testTarget(
            name: "PreviewZooTests",
            dependencies: [
                "PreviewZoo",
                .product(name: "SwiftBookTesting", package: "SwiftBook"),
            ],
            swiftSettings: strict),
    ]
)
