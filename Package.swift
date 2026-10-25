// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

// CI sets SWIFTBOOK_STRICT so warnings fail the build; local builds keep them as warnings while editing.
let strict: [SwiftSetting] =
    Context.environment["SWIFTBOOK_STRICT"] != nil ? [.treatAllWarnings(as: .error)] : []

let package = Package(
    name: "SwiftBook",
    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0")],
    products: [
        // Declarations for a package's own code, such as `SwiftBookConfiguration`. Safe to link
        // into apps: it depends only on SwiftUI.
        .library(name: "SwiftBook", targets: ["SwiftBook"]),
        .library(name: "SwiftBookTesting", targets: ["SwiftBookTesting"]),
        // Linked by the hidden host package that renders a user's stories in its own process.
        .library(name: "SwiftBookRenderer", targets: ["SwiftBookRenderer"]),
        .executable(name: "swiftbook", targets: ["SwiftBookMain"]),
        // The macOS viewer, which `swiftbook view` builds and launches.
        .executable(name: "swiftbook-viewer", targets: ["SwiftBookViewer"]),
    ],
    dependencies: [
        // The major version tracks the Swift release; accept every release consumers might pin.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"605.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // Tests only. Every 0.x release may change alpha features, so pin exactly.
        .package(url: "https://github.com/brandonbloom/Swiftpothesis.git", exact: "0.1.1"),
        // Records what each snapshot renders, so `swiftbook test --changed` can skip the ones a
        // change can't affect. Experimental.
        .package(url: "https://github.com/brandonbloom/SwiftImpact", from: "0.2.0"),
    ],
    targets: [
        .target(name: "SwiftBook", swiftSettings: strict),
        .target(
            name: "SwiftBookCore",
            dependencies: [
                "SwiftBook", "SwiftBookPNGFilters",
                .product(name: "ImpactProbe", package: "SwiftImpact"),
            ],
            swiftSettings: strict),
        // PNG row filters, in C so recording stays fast in debug builds.
        .target(name: "SwiftBookPNGFilters"),
        .target(
            name: "SwiftBookTesting", dependencies: ["SwiftBookCore", "SwiftBookMacros"],
            swiftSettings: strict),
        .macro(
            name: "SwiftBookMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: strict
        ),
        .target(name: "SwiftBookRenderer", dependencies: ["SwiftBookCore"], swiftSettings: strict),
        .target(
            name: "SwiftBookCLI",
            dependencies: [
                "SwiftBookCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ImpactAnalysis", package: "SwiftImpact"),
            ],
            swiftSettings: strict),
        // Not named swiftbook: its module would clash with SwiftBook's on case-insensitive disks.
        .executableTarget(
            name: "SwiftBookMain", dependencies: ["SwiftBookCLI"], swiftSettings: strict),
        .executableTarget(
            name: "SwiftBookViewer", dependencies: ["SwiftBookCore"], swiftSettings: strict),
        .testTarget(
            name: "SwiftBookCoreTests",
            dependencies: [
                "SwiftBookCore", .product(name: "Swiftpothesis", package: "Swiftpothesis"),
            ],
            swiftSettings: strict),
        .testTarget(
            name: "SwiftBookViewerTests", dependencies: ["SwiftBookViewer", "SwiftBookCore"],
            swiftSettings: strict),
        .testTarget(
            name: "SwiftBookCLITests",
            dependencies: [
                "SwiftBookCLI", "SwiftBookCore",
                .product(name: "Swiftpothesis", package: "Swiftpothesis"),
            ],
            swiftSettings: strict),
        .testTarget(
            name: "SwiftBookTestingTests", dependencies: ["SwiftBookTesting", "SwiftBookCore"],
            swiftSettings: strict),
        .testTarget(
            name: "SwiftBookMacrosTests",
            dependencies: [
                "SwiftBookMacros",
                .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosGenericTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: strict),
    ]
)
