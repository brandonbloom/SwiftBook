#if os(macOS)
    import Foundation
    import SwiftBookCore
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
    }
#endif
