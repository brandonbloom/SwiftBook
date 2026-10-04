// swift-tools-version: 6.2

import PackageDescription

// The website's sample app: a few good-looking previews that the site's figures, failures,
// and transcripts are made from. scripts/site-assets renders it.
let package = Package(
    name: "Wander",
    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0")],
    products: [
        .library(name: "Wander", targets: ["Wander"])
    ],
    dependencies: [
        .package(name: "SwiftBook", path: "../..")
    ],
    targets: [
        .target(name: "Wander"),
        .testTarget(
            name: "WanderTests",
            dependencies: [
                "Wander", .product(name: "SwiftBookTesting", package: "SwiftBook"),
            ]),
    ]
)
