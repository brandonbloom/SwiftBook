// swift-tools-version: 6.2

import PackageDescription

// A fixture covering every preview form and the content that tends to render wrong. SwiftBook's
// discovery, adapter, and renderers test against it, and it's the canary for Xcode changes.
let package = Package(
    name: "PreviewZoo",
    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "PreviewZoo", targets: ["PreviewZoo"])
    ],
    targets: [
        .target(name: "PreviewZoo", swiftSettings: [.treatAllWarnings(as: .error)])
    ]
)
