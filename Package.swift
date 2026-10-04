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
        .library(name: "SwiftBookCore", targets: ["SwiftBookCore"]),
        .library(name: "SwiftBookTesting", targets: ["SwiftBookTesting"]),
        // Linked by the hidden host package that renders a user's stories in its own process.
        .library(name: "SwiftBookRenderer", targets: ["SwiftBookRenderer"]),
        .executable(name: "swiftbook", targets: ["swiftbook"]),
    ],
    dependencies: [
        // The major version tracks the Swift release; accept every release consumers might pin.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"605.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(name: "SwiftBookCore", swiftSettings: strict),
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
            ],
            swiftSettings: strict),
        .executableTarget(
            name: "swiftbook", dependencies: ["SwiftBookCLI"], swiftSettings: strict),
        .testTarget(
            name: "SwiftBookCoreTests", dependencies: ["SwiftBookCore"], swiftSettings: strict),
        .testTarget(
            name: "SwiftBookCLITests", dependencies: ["SwiftBookCLI", "SwiftBookCore"],
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
