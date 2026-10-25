#if os(macOS)
    import Foundation

    /// The hidden package that builds a renderer for a user's package, under its
    /// `.build/swiftbook/renderer`.
    ///
    /// The host's executable links every library product of the user's package and SwiftBook's
    /// renderer, which discovers the stories at runtime. It depends on SwiftBook exactly as the
    /// user's package resolved it, so the two can't disagree. Nothing in it is specific to the
    /// user's code, so it's rewritten only when the package's products or dependencies change.
    package struct RendererHost: Sendable {
        /// The user's package.
        package let package: URL
        /// Where the host package lives.
        package var directory: URL { package.appending(path: ".build/swiftbook/renderer") }
        /// Where SwiftPM builds it: the host package's `.build`, unless given a scratch path.
        package let buildDirectory: URL
        /// Arguments naming the scratch path, if there is one.
        let scratchArguments: [String]
        /// Arguments added to each `swift build`: the scratch path's, and any others, such as to
        /// instrument the build.
        let buildArguments: [String]

        static let name = "SwiftBookRendererHost"

        /// A host for `package`. A build with other `buildArguments` takes a `scratchPath` of its
        /// own, so switching between them doesn't rebuild everything.
        package init(package: URL, scratchPath: URL? = nil, buildArguments: [String] = []) {
            self.package = package
            buildDirectory =
                scratchPath
                ?? package.appending(
                    path: ".build/swiftbook/renderer/.build", directoryHint: .isDirectory)
            scratchArguments = scratchPath.map { ["--scratch-path", $0.path] } ?? []
            self.buildArguments = scratchArguments + buildArguments
        }

        /// Writes the host package if it changed and builds it, returning the renderer
        /// executable. `log` receives the build's output.
        package func build(log: @Sendable (String) -> Void = { _ in }) throws -> URL {
            try write()
            let arguments =
                ["swift", "build", "--package-path", directory.path, "--product", Self.name]
                + buildArguments
            guard let result = Shell.run(arguments) else {
                throw RendererError(description: "swift isn't available")
            }
            log(result.output + "\n" + result.error)
            guard result.succeeded else {
                let output = result.output + "\n" + result.error
                throw RendererError(
                    description:
                        "couldn't build the renderer for \(package.path):\n\(Self.diagnostics(in: output))"
                )
            }
            // Where SwiftPM puts a debug build. Asking it with --show-bin-path takes most of a
            // second, so only if the product isn't there.
            var products = buildDirectory.appending(path: "debug", directoryHint: .isDirectory)
            if !FileManager.default.isExecutableFile(
                atPath: products.appending(path: Self.name).path)
            {
                guard
                    let binPath = Shell.run(
                        ["swift", "build", "--package-path", directory.path, "--show-bin-path"]
                            + buildArguments),
                    binPath.succeeded
                else {
                    throw RendererError(description: "can't find the renderer's build directory")
                }
                products = URL(filePath: binPath.output, directoryHint: .isDirectory)
            }
            return try macApp(around: products).appending(path: "Contents/MacOS/\(Self.name)")
        }

        /// Makes the Mac renderer an app around the build's `products`, returning the app.
        ///
        /// A bare executable started by an app registers with macOS as that app, a regular one
        /// with its icon, until it changes its activation policy, and macOS can leave that Dock
        /// tile behind after it exits. An app of its own, as a UI element, never gets a tile
        /// yet can still show interactive windows and take focus. Its executable and resources
        /// are the build's, by symbolic links, so it needs no copying and finds resource
        /// bundles and frameworks where SwiftPM put them.
        func macApp(around products: URL) throws -> URL {
            let app = buildDirectory.appending(path: "swiftbook-macOS/\(Self.name).app")
            let contents = app.appending(path: "Contents")
            let plist: [String: Any] = [
                "CFBundleIdentifier": bundleID,
                "CFBundleExecutable": Self.name,
                "CFBundleName": "SwiftBook Renderer",
                "CFBundlePackageType": "APPL",
                "LSUIElement": true,
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try Self.write(
                String(decoding: data, as: UTF8.self), to: contents.appending(path: "Info.plist"))
            // Resolved, since SwiftPM repoints .build/debug at whichever platform built last.
            let resolved = products.resolvingSymlinksInPath()
            for name in ["MacOS", "Resources"] {
                try Self.link(contents.appending(path: name), to: resolved)
            }
            return app
        }

        /// The renderer's bundle identifier, on every platform.
        var bundleID: String {
            "dev.swiftbook.renderer." + Self.bundleIDComponent(package.lastPathComponent)
        }

        /// A simulator platform the renderer app can be built for.
        package enum SimulatorPlatform: String, Sendable, CaseIterable {
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
        package struct App: Sendable {
            package let url: URL
            package let bundleID: String
        }

        /// Writes the host package if it changed and builds the renderer as an app for
        /// `platform`'s simulator. `log` receives the build's output.
        ///
        /// SwiftPM builds the executable, and SwiftBook wraps it in a minimal app: an
        /// `Info.plist` with a scene manifest, the package's resource bundles, and an ad hoc
        /// signature.
        package func buildApp(
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
            let target =
                [
                    "--package-path", directory.path, "--triple", platform.triple, "--sdk",
                    sdkPath.output,
                ] + buildArguments
            guard let result = Shell.run(["swift", "build", "--product", Self.name] + target) else {
                throw RendererError(description: "swift isn't available")
            }
            log(result.output + "\n" + result.error)
            guard result.succeeded else {
                throw RendererError(
                    description:
                        "couldn't build the \(platform) renderer for \(package.path):\n\(Self.diagnostics(in: result.output + "\n" + result.error))"
                )
            }
            guard let binPath = Shell.run(["swift", "build", "--show-bin-path"] + target),
                binPath.succeeded
            else { throw RendererError(description: "can't find the renderer's build directory") }
            let products = URL(filePath: binPath.output, directoryHint: .isDirectory)

            let app = buildDirectory.appending(
                path: "swiftbook-\(platform.rawValue)/\(Self.name).app")
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

        /// The compiler's errors in a failed build's output, or its end if there are none.
        /// Build logs bury them under long command lines.
        package static func diagnostics(in output: String) -> String {
            let errors = output.split(separator: "\n")
                .filter { $0.contains("error:") && !$0.hasPrefix("error: Build failed") }
            var seen = Set<Substring>()
            let unique = errors.filter { seen.insert($0).inserted }
            return unique.isEmpty
                ? String(output.suffix(4000)) : unique.prefix(20).joined(separator: "\n")
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
            defer {
                // Mirror `swift package edit` on SwiftBook, so the renderer runs the same source.
                if let dependency = try? swiftBookDependency(), let edited = dependency.edited {
                    try? edit(at: edited, identity: dependency.identity)
                }
            }
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

        /// Puts the host's SwiftBook dependency in edit mode at `path`, unless it already is.
        func edit(at path: String, identity: String) throws {
            let state = buildDirectory.appending(path: "workspace-state.json")
            if let text = try? String(contentsOf: state, encoding: .utf8),
                text.contains("\"\(path)\"")
            {
                return
            }
            guard
                let result = Shell.run(
                    ["swift", "package", "--package-path", directory.path] + scratchArguments
                        + ["edit", identity, "--path", path]),
                result.succeeded
            else {
                throw RendererError(
                    description: "couldn't edit the renderer's SwiftBook dependency at \(path)")
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
                        \(swiftBook.declaration),
                    ],
                    targets: [
                        .executableTarget(
                            name: "\(Self.name)",
                            dependencies: [
                                .product(name: "SwiftBookRenderer", package: \(Self.literal(swiftBook.identity))),
                                \(products.joined(separator: ",\n                ")),
                            ])
                    ]
                )

                """
        }

        /// The host's dependency on SwiftBook: the same location and revision the user's
        /// package resolved. `identity` is how SwiftPM names it, which for a path dependency
        /// comes from the checkout's directory name. With `swift package edit` in effect,
        /// `edited` is the working copy the host must also edit.
        func swiftBookDependency() throws -> (
            declaration: String, identity: String, edited: String?
        ) {
            let graph = try Self.json(
                ["swift", "package", "show-dependencies", "--format", "json"], in: package)
            guard
                // The manifest's name, since a checkout may be in a directory of any name.
                let node = (graph["dependencies"] as? [[String: Any]])?.first(where: {
                    ($0["name"] as? String) == "SwiftBook"
                }),
                let identity = node["identity"] as? String,
                let location = node["url"] as? String
            else {
                throw RendererError(
                    description: "\(package.path) doesn't depend on SwiftBook directly.")
            }
            if location.hasPrefix("/") {
                return (".package(path: \(Self.literal(location)))", identity, nil)
            }
            // A remote dependency checked out anywhere but .build/checkouts is being edited.
            let edited = (node["path"] as? String).flatMap {
                $0.contains("/.build/checkouts/") ? nil : $0
            }
            guard
                let revision = pinnedRevision(of: identity)
                    ?? (edited != nil ? editBaseRevision(of: identity) : nil)
            else {
                throw RendererError(
                    description:
                        "\(package.path)/Package.resolved doesn't pin SwiftBook; run swift package resolve."
                )
            }
            return (
                ".package(url: \(Self.literal(location)), revision: \(Self.literal(revision)))",
                identity, edited
            )
        }

        /// The revision `Package.resolved` pins the package with `identity` to.
        private func pinnedRevision(of identity: String) -> String? {
            let pins = (try? Data(contentsOf: package.appending(path: "Package.resolved")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let pin = (pins?["pins"] as? [[String: Any]])?.first {
                ($0["identity"] as? String) == identity
            }
            return (pin?["state"] as? [String: Any])?["revision"] as? String
        }

        /// The revision an edited SwiftBook was checked out at before editing. `Package.resolved`
        /// drops edited dependencies, but the workspace state remembers it.
        private func editBaseRevision(of identity: String) -> String? {
            let state =
                (try? Data(contentsOf: package.appending(path: ".build/workspace-state.json")))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let dependencies =
                (state?["object"] as? [String: Any])?["dependencies"] as? [[String: Any]]
            let dependency = dependencies?.first {
                (($0["packageRef"] as? [String: Any])?["identity"] as? String) == identity
            }
            let base = ((dependency?["basedOn"] as? [String: Any])?["state"] as? [String: Any])
            return (base?["checkoutState"] as? [String: Any])?["revision"] as? String
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

        /// Makes `url` a symbolic link to `destination`, unless it already is.
        private static func link(_ url: URL, to destination: URL) throws {
            let manager = FileManager.default
            if (try? manager.destinationOfSymbolicLink(atPath: url.path)) == destination.path {
                return
            }
            try? manager.removeItem(at: url)
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try manager.createSymbolicLink(at: url, withDestinationURL: destination)
        }

        /// `text` as a Swift string literal.
        private static func literal(_ text: String) -> String {
            "\""
                + text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
    }
#endif
