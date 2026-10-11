// swift-tools-version: 6.2

import PackageDescription

// A package that sets a tint for every story through SwiftBookConfiguration, with the color in
// an asset catalog, as an app's AccentColor would be. RendererHostTests renders it.
let package = Package(
    name: "TintZoo",
    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "TintZoo", targets: ["TintZoo"])
    ],
    dependencies: [
        .package(name: "SwiftBook", path: "../..")
    ],
    targets: [
        .target(
            name: "TintZoo", dependencies: [.product(name: "SwiftBook", package: "SwiftBook")],
            resources: [.process("Resources")])
    ]
)
