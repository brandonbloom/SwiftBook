#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Swiftpothesis
    import Testing

    @testable import SwiftBookCLI

    @Suite struct TestCommandTests {
        @Test func findsTheDevicesWithReferences() throws {
            let store = SnapshotStore(
                root: FileManager.default.temporaryDirectory.appending(
                    path: "TestCommandTests-\(UUID())/Snapshots", directoryHint: .isDirectory))
            #expect(TestCommand.devicesWithReferences(in: store).isEmpty)
            let story = store.root.appending(path: "M/G/S")
            try FileManager.default.createDirectory(at: story, withIntermediateDirectories: true)
            for name in ["tv.dark.png", "mac.light.png", "iphone.light.xxxLarge.png", "notes.txt"] {
                try Data().write(to: story.appending(path: name))
            }
            #expect(TestCommand.devicesWithReferences(in: store) == [.mac, .iphone, .tv])
        }

        @Test func parsesDevicesAndPlatformNames() throws {
            let command = try #require(
                SwiftBookCommand.parseAsRoot([
                    "test", "--device", "ipad", "--platform", "tvos", "--device", "ios",
                    "--record", "never",
                ]) as? TestCommand)
            #expect(command.devices == [.ipad, .tv, .iphone])
            #expect(command.record == .never)
            #expect(throws: (any Error).self) {
                try SwiftBookCommand.parseAsRoot(["test", "--device", "watch"])
            }
        }

        @Test func reportsEachSnapshotInJUnit() {
            var results = TestCommand.Results()
            results.add(
                (
                    [
                        .init(device: .iphone, subject: "M/G/S (iphone.light)"),
                        .init(
                            device: .iphone, subject: "M/G/S (iphone.dark)",
                            failure: "doesn't match\ndetails"),
                    ], true
                ))
            #expect(results.failed)
            let xml = results.junit()
            #expect(xml.contains(#"<testsuite name="iphone" tests="2" failures="1">"#))
            #expect(
                xml.contains(#"<failure message="doesn't match">doesn't match\#ndetails</failure>"#)
            )
        }

        @Test func shellQuotingSurvivesTheShell() async {
            // Arguments can't hold NUL.
            let text = String.arbitrary(Unicode.Scalar.arbitrary.filter { $0 != "\0" })
            // A quote and a combining mark make one Character, which quoting once missed.
            await forAll(text, examples: ["'\u{301}"]) { text in
                let process = Process()
                process.executableURL = URL(filePath: "/bin/sh")
                process.arguments = [
                    "-c",
                    #"set -- "# + TestCommand.Results.shellQuoted(text)
                        + #"; printf '%s:%s' "$#" "$1""#,
                ]
                let output = Pipe()
                process.standardOutput = output
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                #expect(String(decoding: data, as: UTF8.self) == "1:\(text)")
            }
        }

        @Test func summarizesTheFailures() {
            var results = TestCommand.Results()
            #expect(results.failureSummary() == nil)
            let plain = StoryID(module: "M", group: "G", name: "S")
            let spaced = StoryID(module: "M", group: "G", name: "Bob's row")
            results.add(
                (
                    [
                        .init(device: .iphone, subject: "M/G/S (iphone.light)", story: plain),
                        .init(
                            device: .iphone, subject: "M/G/S (iphone.dark)", story: plain,
                            failure: "doesn't match"),
                        .init(
                            device: .iphone, subject: "M/G/Bob's row (iphone.light)",
                            story: spaced, failure: "doesn't match"),
                        .init(
                            device: .iphone, subject: "M/G/Bob's row (iphone.dark)",
                            story: spaced, failure: "doesn't match"),
                        .init(device: .mac, subject: "swift test", failure: "exited with 1"),
                    ], true
                ))
            #expect(
                results.failureSummary() == """
                    ✗ 4 failed: M/G/S (iphone.dark), M/G/Bob's row (iphone.light), \
                    M/G/Bob's row (iphone.dark), swift test
                      To look at them: swiftbook render M/G/S 'M/G/Bob'\\''s row' --device iphone
                    """)
        }
    }
#endif
