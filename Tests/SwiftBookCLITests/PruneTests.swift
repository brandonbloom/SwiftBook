#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookCLI

    @Suite struct PruneTests {
        let store = SnapshotStore(
            root: FileManager.default.temporaryDirectory.appending(
                path: "PruneTests-\(UUID())/Snapshots", directoryHint: .isDirectory))

        func reference(_ story: StoryID, _ variant: String = "mac.light") throws {
            let url = store.url(for: story, device: .mac, environment: RenderEnvironment())
                .deletingLastPathComponent().appending(path: "\(variant).png")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }

        @Test func findsStoriesThatNoLongerExistInLinkedModules() throws {
            let live = StoryID(module: "M", group: "G", name: "Slash / colon: and émoji 🌙")
            let gone = StoryID(module: "M", group: "G", name: "Gone")
            let unlinked = StoryID(module: "Other", group: "G", name: "S")
            for story in [live, gone, unlinked] { try reference(story) }
            try reference(live, "iphone.dark")

            let orphans = PruneCommand.orphans(in: store, stories: [StoryInfo(id: live)])
            #expect(orphans.map(\.lastPathComponent) == ["Gone"])
        }
    }
#endif
