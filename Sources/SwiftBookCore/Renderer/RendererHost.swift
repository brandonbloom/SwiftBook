#if os(macOS)
    import Foundation

    /// The hidden package that builds a renderer for a user's package, under its
    /// `.build/swiftbook/renderer`.
    ///
    /// The host's executable links every library product of the user's package and SwiftBook's
    /// renderer, which discovers the stories at runtime. It depends on SwiftBook exactly as the
    /// user's package resolved it, so the two can't disagree. Nothing in it is specific to the
    /// user's code, so it's rewritten only when the package's products or dependencies change.
    public struct RendererHost: Sendable {
        /// The user's package.
        public let package: URL
        /// Where the host package lives.
        public var directory: URL { package.appending(path: ".build/swiftbook/renderer") }

        static let name = "SwiftBookRendererHost"

        public init(package: URL) {
            self.package = package
        }

        /// Writes the host package if it changed and builds it, returning the renderer
        /// executable. `log` receives the build's output.
        public func build(log: @Sendable (String) -> Void = { _ in }) throws -> URL {
            try write()
            let arguments = [
                "swift", "build", "--package-path", directory.path, "--product", Self.name,
            ]
            guard let result = Shell.run(arguments) else {
                throw RendererError(description: "swift isn't available")
            }
            log(result.output + "\n" + result.error)
            guard result.succeeded else {
                let output = result.output + "\n" + result.error
                throw RendererError(
                    description:
                        "couldn't build the renderer for \(package.path):\n\(output.suffix(4000))")
            }
            guard
                let binPath = Shell.run(
                    ["swift", "build", "--package-path", directory.path, "--show-bin-path"]),
                binPath.succeeded
            else { throw RendererError(description: "can't find the renderer's build directory") }
            return URL(filePath: binPath.output).appending(path: Self.name)
        }

        /// A simulator platform the renderer app can be built for.
        public enum SimulatorPlatform: String, Sendable, CaseIterable {
            case iOS, tvOS

            var triple: String {
                switch self {
                case .iOS: "arm64-apple-ios27.0-simulator"
                case .tvOS: "arm64-apple-tvos27.0-simulator"
                }
            }

            var sdk: String {
                switch self {
                case .iOS: "iphonesimulator"
                case .tvOS: "appletvsimulator"
                }
            }

            /// The platform as `vtool` takes it: by name, or by number (`PLATFORM_TVOSSIMULATOR`)
            /// where it has none.
            var vtoolPlatform: String {
                switch self {
                case .iOS: "iossim"
                case .tvOS: "8"
                }
            }

            var plistPlatform: String {
                switch self {
                case .iOS: "iPhoneSimulator"
                case .tvOS: "AppleTVSimulator"
                }
            }

            /// `UIDeviceFamily`: iPhone and iPad, or TV.
            var deviceFamilies: [Int] {
                switch self {
                case .iOS: [1, 2]
                case .tvOS: [3]
                }
            }
        }

        /// A built renderer app.
        public struct App: Sendable {
            public let url: URL
            public let bundleID: String
        }

        /// Writes the host package if it changed and builds the renderer as an app for
        /// `platform`'s simulator. `log` receives the build's output.
        ///
        /// SwiftPM builds the executable, and SwiftBook wraps it in a minimal app: an
        /// `Info.plist` with a scene manifest, the package's resource bundles, and an ad hoc
        /// signature.
        public func buildApp(
            for platform: SimulatorPlatform, log: @Sendable (String) -> Void = { _ in }
        ) throws -> App {
            try write()
            guard let sdkPath = Shell.run(["xcrun", "--sdk", platform.sdk, "--show-sdk-path"]),
                sdkPath.succeeded,
                let sdkVersion = Shell.run(["xcrun", "--sdk", platform.sdk, "--show-sdk-version"]),
                sdkVersion.succeeded
            else {
                throw RendererError(description: "the \(platform) simulator SDK isn't installed")
            }
            let target = [
                "--package-path", directory.path, "--triple", platform.triple, "--sdk",
                sdkPath.output,
            ]
            guard let result = Shell.run(["swift", "build", "--product", Self.name] + target) else {
                throw RendererError(description: "swift isn't available")
            }
            log(result.output + "\n" + result.error)
            guard result.succeeded else {
                throw RendererError(
                    description:
                        "couldn't build the \(platform) renderer for \(package.path):\n\((result.output + "\n" + result.error).suffix(4000))"
                )
            }
            guard let binPath = Shell.run(["swift", "build", "--show-bin-path"] + target),
                binPath.succeeded
            else { throw RendererError(description: "can't find the renderer's build directory") }
            let products = URL(filePath: binPath.output, directoryHint: .isDirectory)

            let app = directory.appending(
                path: ".build/swiftbook-\(platform.rawValue)/\(Self.name).app")
            let manager = FileManager.default
            try? manager.removeItem(at: app)
            try manager.createDirectory(at: app, withIntermediateDirectories: true)
            // SwiftPM stamps the deployment target as the SDK version, and UIKit matches its
            // behavior to that stamp: List headers render in an older style. Stamp the real SDK.
            let stamped = Shell.run([
                "vtool", "-set-build-version", platform.vtoolPlatform, "27.0", sdkVersion.output,
                "-replace", "-output", app.appending(path: Self.name).path,
                products.appending(path: Self.name).path,
            ])
            guard stamped?.succeeded == true else {
                throw RendererError(
                    description: "vtool couldn't stamp the renderer: \(stamped?.error ?? "")")
            }
            for bundle
                in (try? manager.contentsOfDirectory(at: products, includingPropertiesForKeys: nil))?
                .filter({ $0.pathExtension == "bundle" }) ?? []
            {
                // iOS bundles are flat. One with a top-level Resources directory looks like a
                // macOS bundle to codesign, which then fails with "bundle format unrecognized".
                if manager.fileExists(atPath: bundle.appending(path: "Resources").path) {
                    throw RendererError(
                        description:
                            "\(bundle.lastPathComponent) has a top-level Resources directory, which iOS and tvOS bundles can't. Rename the directory the package copies as a resource, such as .copy(\"Resources\"), to something else."
                    )
                }
                try manager.copyItem(at: bundle, to: app.appending(path: bundle.lastPathComponent))
            }
            let bundleID =
                "dev.swiftbook.renderer." + Self.bundleIDComponent(package.lastPathComponent)
            let plist: [String: Any] = [
                "CFBundleIdentifier": bundleID,
                "CFBundleExecutable": Self.name,
                "CFBundleName": "SwiftBook Renderer",
                "CFBundlePackageType": "APPL",
                "CFBundleVersion": "1",
                "CFBundleShortVersionString": "1.0",
                "CFBundleSupportedPlatforms": [platform.plistPlatform],
                "MinimumOSVersion": "27.0",
                "UIDeviceFamily": platform.deviceFamilies,
                "UILaunchScreen": [String: Any](),
                // SDK 27 requires the scene lifecycle; the app delegate configures the scene.
                "UIApplicationSceneManifest": ["UIApplicationSupportsMultipleScenes": false],
                // Stories may ask for any orientation, and the app rotates to each. Full screen
                // keeps iPad windowing from resizing it.
                "UISupportedInterfaceOrientations": [
                    "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
                    "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
                ],
                "UIRequiresFullScreen": true,
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: app.appending(path: "Info.plist"))
            let signed = Shell.run(["codesign", "--force", "--deep", "--sign", "-", app.path])
            guard signed?.succeeded == true else {
                throw RendererError(
                    description: "couldn't sign the renderer app: \(signed?.error ?? "")")
            }
            return App(url: app, bundleID: bundleID)
        }

        /// `name` with only the characters a bundle identifier allows.
        static func bundleIDComponent(_ name: String) -> String {
            let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
            let cleaned = String(name.map { allowed.contains($0) ? $0 : "-" })
            return cleaned.isEmpty ? "package" : cleaned
        }

        /// Writes the host's manifest, entry point, and pins, leaving unchanged files alone so
        /// builds stay incremental.
        func write() throws {
            let manifest = try self.manifest()
            try Self.write(manifest, to: directory.appending(path: "Package.swift"))
            try Self.write(
                """
                // Generated by SwiftBook.
                import SwiftBookRenderer

                RendererServer.main()

                """, to: directory.appending(path: "Sources/\(Self.name)/main.swift"))
            // Start from the user's pins, so shared dependencies resolve to the same versions.
            let pins = package.appending(path: "Package.resolved")
            if let resolved = try? String(contentsOf: pins, encoding: .utf8) {
                try Self.write(resolved, to: directory.appending(path: "Package.resolved"))
            }
        }

        /// The host's `Package.swift`.
        func manifest() throws -> String {
            let description = try Self.json(["swift", "package", "dump-package"], in: package)
            let libraries = (description["products"] as? [[String: Any]] ?? []).compactMap {
                product -> String? in
                guard let type = product["type"] as? [String: Any], type["library"] != nil else {
                    return nil
                }
                return product["name"] as? String
            }
            guard !libraries.isEmpty else {
                throw RendererError(
                    description:
                        "\(package.path) has no library products. SwiftBook renders previews in library targets."
                )
            }
            let swiftBook = try swiftBookDependency()
            let identity = package.lastPathComponent.lowercased()
            let products = libraries.map {
                ".product(name: \(Self.literal($0)), package: \(Self.literal(identity)))"
            }
            return """
                // swift-tools-version: 6.2
                // Generated by SwiftBook: renders \(package.lastPathComponent)'s stories in a process of their own.

                import PackageDescription

                let package = Package(
                    name: "\(Self.name)",
                    platforms: [.macOS("27.0"), .iOS("27.0"), .tvOS("27.0")],
                    dependencies: [
                        .package(path: \(Self.literal(package.path))),
                        \(swiftBook),
                    ],
                    targets: [
                        .executableTarget(
                            name: "\(Self.name)",
                            dependencies: [
                                .product(name: "SwiftBookRenderer", package: "swiftbook"),
                                \(products.joined(separator: ",\n                ")),
                            ])
                    ]
                )

                """
        }

        /// The host's dependency on SwiftBook: the same location and revision the user's
        /// package resolved.
        func swiftBookDependency() throws -> String {
            let graph = try Self.json(
                ["swift", "package", "show-dependencies", "--format", "json"], in: package)
            guard
                let node = (graph["dependencies"] as? [[String: Any]])?.first(where: {
                    ($0["identity"] as? String) == "swiftbook"
                }),
                let location = node["url"] as? String
            else {
                throw RendererError(
                    description: "\(package.path) doesn't depend on SwiftBook directly.")
            }
            if location.hasPrefix("/") { return ".package(path: \(Self.literal(location)))" }
            let pins = (try? Data(contentsOf: package.appending(path: "Package.resolved")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            guard
                let pin = (pins?["pins"] as? [[String: Any]])?.first(where: {
                    ($0["identity"] as? String) == "swiftbook"
                }),
                let revision = (pin["state"] as? [String: Any])?["revision"] as? String
            else {
                throw RendererError(
                    description:
                        "\(package.path)/Package.resolved doesn't pin SwiftBook; run swift package resolve."
                )
            }
            return ".package(url: \(Self.literal(location)), revision: \(Self.literal(revision)))"
        }

        private static func json(_ arguments: [String], in directory: URL) throws -> [String: Any] {
            guard let result = Shell.run(arguments, in: directory), result.succeeded,
                let object = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any]
            else {
                throw RendererError(
                    description:
                        "\(arguments.joined(separator: " ")) failed in \(directory.path)")
            }
            return object
        }

        private static func write(_ text: String, to url: URL) throws {
            if (try? String(contentsOf: url, encoding: .utf8)) == text { return }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }

        /// `text` as a Swift string literal.
        private static func literal(_ text: String) -> String {
            "\""
                + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
    }
#endif
