#if os(macOS)
    import Foundation
    import SwiftUI
    import Swiftpothesis
    import Testing

    @testable import SwiftBookCore

    /// The renderer protocol and process supervision, against scripted fake renderers.
    @Suite struct RendererProcessTests {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "RendererProcessTests-\(UUID())", directoryHint: .isDirectory)

        static let hello = #"{"protocolVersion":1,"swiftBookVersion":"test","platform":"macOS"}"#

        /// An executable shell script.
        func renderer(_ body: String) throws -> URL {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: "renderer-\(UUID()).sh")
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
            return url
        }

        @Test func roundTripsTheRenderEnvironment() async {
            let finite = Double.arbitrary(allowNaN: false, allowInfinity: false)
            let environments = zip(
                element(of: RenderEnvironment.Appearance.allCases), finite, String.arbitrary,
                String.arbitrary, element(of: DynamicTypeSize.allCases),
                element(of: [LayoutDirection.leftToRight, .rightToLeft]), finite, finite
            ).map { appearance, scale, locale, timeZone, size, direction, width, height in
                var environment = RenderEnvironment()
                environment.appearance = appearance
                environment.scale = scale
                environment.localeIdentifier = locale
                environment.timeZoneIdentifier = timeZone
                environment.dynamicTypeSize = size
                environment.layoutDirection = direction
                environment.deviceWidth = width
                environment.deviceHeight = height
                return environment
            }
            await forAll(environments) { environment in
                let data = try JSONEncoder().encode(environment)
                #expect(try JSONDecoder().decode(RenderEnvironment.self, from: data) == environment)
            }
        }

        @Test func answersRequestsInOrder() throws {
            // Answers every request with an error naming its id, then exits at end of input.
            let process = try RendererProcess(
                executable: renderer(
                    """
                    echo '\(Self.hello)'
                    while read line; do
                      id=$(echo "$line" | sed 's/.*"id":\\([0-9]*\\).*/\\1/')
                      echo "{\\"id\\":$id,\\"error\\":\\"no story $id\\"}"
                    done
                    """))
            #expect(process.hello.swiftBookVersion == "test")
            for id in 1...3 {
                #expect {
                    try process.render(StoryID(module: "M", group: "G", name: "S"))
                } throws: { ($0 as? RendererError)?.description == "no story \(id)" }
            }
            process.shutdown()
            #expect(!process.isRunning)
        }

        @Test func stopsARendererThatHangs() throws {
            let process = try RendererProcess(
                executable: renderer("echo '\(Self.hello)'\nsleep 60"))
            #expect {
                try process.stories(timeout: .milliseconds(300))
            } throws: {
                ($0 as? RendererError)?.description.contains("took longer than") == true
            }
            #expect(!process.isRunning)
        }

        @Test func explainsACrashWithWhatTheRendererSaid() throws {
            let process = try RendererProcess(
                executable: renderer(
                    "echo '\(Self.hello)'\nread line\necho 'Fatal error: boom' >&2\nexit 6"))
            #expect {
                try process.stories()
            } throws: { error in
                let description = (error as? RendererError)?.description ?? ""
                return description.contains("exited with status 6")
                    && description.contains("Fatal error: boom")
            }
        }

        /// A renderer that hangs on its first render if `marker` doesn't exist yet, creating it,
        /// and otherwise answers renders with an error naming its process.
        func hangsOnce(marker: URL) throws -> URL {
            try renderer(
                """
                echo '\(Self.hello)'
                while read line; do
                  id=$(echo "$line" | sed 's/.*"id":\\([0-9]*\\).*/\\1/')
                  if [ ! -e '\(marker.path)' ]; then touch '\(marker.path)'; sleep 60; fi
                  echo "{\\"id\\":$id,\\"error\\":\\"served by $$\\"}"
                done
                """)
        }

        @Test func restartsAndRetriesARendererThatHangs() throws {
            let script = try hangsOnce(marker: directory.appending(path: "hung"))
            let renderer = try RestartingRenderer { try RendererProcess(executable: script) }
            // The retry reaches a fresh renderer, which reports its own error: the story's fault,
            // not a hang.
            #expect {
                try renderer.render(
                    StoryID(module: "M", group: "G", name: "S"), timeout: .milliseconds(500))
            } throws: { ($0 as? RendererError)?.description.hasPrefix("served by") == true }
            #expect(renderer.restarts == 1)
            renderer.shutdown()
        }

        @Test func reportsAStoryThatCrashesEveryRenderer() throws {
            let script = try renderer("echo '\(Self.hello)'\nread line\nexit 6")
            let renderer = try RestartingRenderer { try RendererProcess(executable: script) }
            #expect {
                try renderer.render(StoryID(module: "M", group: "G", name: "S"))
            } throws: {
                ($0 as? RendererError)?.description.contains(
                    "failed the same way on a restarted renderer")
                    == true
            }
            #expect(renderer.restarts == 1)
            // The next request still gets a renderer, and its own retry.
            #expect(throws: RendererError.self) {
                try renderer.render(StoryID(module: "M", group: "G", name: "T"))
            }
            #expect(renderer.restarts == 3)
        }

        @Test func refusesAnotherProtocolVersion() throws {
            #expect {
                try RendererProcess(
                    executable: renderer(
                        #"echo '{"protocolVersion":99,"swiftBookVersion":"9","platform":"macOS"}'"#
                    ))
            } throws: { ($0 as? RendererError)?.description.contains("protocol 99") == true }
        }
    }

    /// A real renderer built for the zoo, end to end.
    @Suite(.serialized) struct RendererHostTests {
        static let zoo = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/PreviewZoo", directoryHint: .isDirectory)

        @Test func rendersTheZooLikeSwiftTest() throws {
            let executable = try RendererHost(package: Self.zoo).build()
            let renderer = try RendererProcess(
                executable: executable, environment: ["SWIFTBOOK_CAPTURE": "emulated"])
            defer { renderer.shutdown() }
            #expect(renderer.hello.protocolVersion == RendererProtocol.version)

            let stories = try renderer.stories(check: true)
            #expect(stories.count >= 30)
            #expect(stories.allSatisfy { $0.error == nil })
            #expect(
                stories.contains {
                    $0.id.description == "PreviewZoo/Arguments/Badge arguments / SALE"
                })

            // The same render as the committed reference, made by swift test.
            let card = StoryID(module: "PreviewZoo", group: "Card", name: "Card")
            let png = try renderer.render(card)
            let store = SnapshotStore(root: Self.zoo.appending(path: "Snapshots"))
            let reference = try Data(
                contentsOf: store.url(for: card, device: .mac, environment: RenderEnvironment()))
            let diff = try ImageDiff.compare(
                expected: SnapshotStore.image(reference, at: "reference"),
                actual: SnapshotStore.image(png, at: "render"))
            #expect(diff.isIdentical)

            #expect(throws: RendererError.self) {
                try renderer.render(StoryID(module: "PreviewZoo", group: "Card", name: "Nope"))
            }
            // A failed request leaves the renderer serving.
            #expect(try renderer.render(card) == png)
        }

        static let iOSRuntimeInstalled =
            Shell.run(["xcrun", "simctl", "list", "runtimes"])?.output
            .split(separator: "\n").contains { $0.hasPrefix("iOS 27") || $0.hasPrefix("iOS 28") }
            ?? false

        @Test(.enabled(if: iOSRuntimeInstalled)) func rendersTheZooInTheSimulator() throws {
            let app = try RendererHost(package: Self.zoo).buildApp(for: .iOS)
            // Leased, like the CLI's, so it can't suspend another run's renderer.
            let lease = try SimulatorPool.lease(for: .iphone)
            defer { lease.release() }
            let simulator = lease.simulator
            #expect(simulator.name.hasPrefix("SwiftBook iPhone 17 Pro"))
            let renderer = try RendererProcess(app: app.url, bundleID: app.bundleID, in: simulator)
            defer { renderer.shutdown() }
            #expect(renderer.hello.platform == "iOS")

            let stories = try renderer.stories(check: true)
            #expect(stories.allSatisfy { $0.error == nil })
            #expect(stories.contains { $0.id.description == "PreviewZoo/PlatformViews/UIView" })
            #expect(!stories.contains { $0.id.description == "PreviewZoo/PlatformViews/NSView" })

            let card = StoryID(module: "PreviewZoo", group: "Card", name: "Card")
            let environment = RenderEnvironment.standard(for: .iphone)
            let png = try renderer.render(card, in: environment)
            let metadata = try #require(try SnapshotMetadata.read(fromPNG: png))
            #expect(metadata.device == "iphone")
            #expect(metadata.platform == "iOS")
            let image = try SnapshotStore.image(png, at: "render")
            // The device layout fills the pinned iPhone's screen, at its scale.
            #expect(image.width == 402 * 3 && image.height == 874 * 3)
            #expect(try renderer.render(card, in: environment) == png)
            #expect(try renderer.renderImage(card, in: environment).glassRegions.isEmpty)

            // Glass is reported where it is: the tab bar and toolbar, not the whole screen.
            let glass = try renderer.renderImage(
                StoryID(module: "PreviewZoo", group: "Hazards", name: "Liquid Glass"),
                in: environment
            ).glassRegions
            #expect(!glass.isEmpty)
            let area = glass.reduce(0) { $0 + $1.width * $1.height }
            #expect(area < image.width * image.height / 4)
        }

        static let tintZoo = zoo.deletingLastPathComponent()
            .appending(path: "TintZoo", directoryHint: .isDirectory)

        /// How many of `png`'s pixels are within a few levels of `hex` (`#RRGGBB`).
        static func pixels(in png: Data, matching hex: String) throws -> Int {
            let target = stride(from: 1, to: 7, by: 2).map {
                Int(hex[hex.index(hex.startIndex, offsetBy: $0)...].prefix(2), radix: 16)!
            }
            let bitmap = try Bitmap(SnapshotStore.image(png, at: "render"))
            return stride(from: 0, to: bitmap.pixels.count, by: 4).filter { offset in
                (0..<3).allSatisfy { abs(Int(bitmap.pixels[offset + $0]) - target[$0]) <= 3 }
            }.count
        }

        @Test func tintsEveryStoryWithTheProjectsColor() throws {
            let executable = try RendererHost(package: Self.tintZoo).build()
            let renderer = try RendererProcess(
                executable: executable, environment: ["SWIFTBOOK_CAPTURE": "emulated"])
            defer { renderer.shutdown() }
            // The configuration also leaves a story out of snapshot tests.
            #expect(
                try renderer.stories().map { "\($0.id) \($0.isTested)" } == [
                    "TintZoo/Tint/Tinted true", "TintZoo/Tint/Viewer only false",
                ])
            let story = StoryID(module: "TintZoo", group: "Tint", name: "Tinted")
            // The asset catalog's AccentColor, light and dark.
            for (appearance, tint) in [
                (RenderEnvironment.Appearance.light, "#0D8D6D"), (.dark, "#189973"),
            ] {
                var environment = RenderEnvironment()
                environment.appearance = appearance
                let png = try renderer.render(story, in: environment)
                #expect(try SnapshotMetadata.read(fromPNG: png)?.tint == tint)
                // The 48-point swatch, at 2x.
                #expect(try Self.pixels(in: png, matching: tint) >= 48 * 48 * 4 * 8 / 10)
            }
        }
    }
#endif
