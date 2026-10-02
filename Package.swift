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
        .executable(name: "swiftbook", targets: ["swiftbook"]),
    ],
    dependencies: [
        // The major version tracks the Swift release; accept every release consumers might pin.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"605.0.0")
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
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: strict
        ),
        .executableTarget(
            name: "swiftbook", dependencies: ["SwiftBookCore"], swiftSettings: strict),
        .testTarget(
            name: "SwiftBookCoreTests", dependencies: ["SwiftBookCore"], swiftSettings: strict),
    ]
)
