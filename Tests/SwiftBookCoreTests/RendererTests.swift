#if os(macOS)
    import Foundation
    import SwiftUI
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

        @Test func roundTripsTheRenderEnvironment() throws {
            var environment = RenderEnvironment()
            environment.appearance = .dark
            environment.dynamicTypeSize = .accessibility3
            environment.layoutDirection = .rightToLeft
            environment.localeIdentifier = "ar"
            let data = try JSONEncoder().encode(environment)
            #expect(try JSONDecoder().decode(RenderEnvironment.self, from: data) == environment)
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
    }
#endif
