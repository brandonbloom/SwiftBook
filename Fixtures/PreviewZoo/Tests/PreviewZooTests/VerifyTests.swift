#if os(macOS)
    import Foundation
    import SwiftBookTesting
    import Testing

    /// Recording, matching, and mismatching against a scratch store, end to end.
    @MainActor @Suite struct VerifyTests {
        let store = SnapshotStore(
            root: FileManager.default.temporaryDirectory.appending(
                path: "VerifyTests-\(UUID())/Snapshots"))

        func story(_ group: String, _ name: String) async throws -> TestStory {
            try #require(await SwiftBook.stories().first { $0.id == "PreviewZoo/\(group)/\(name)" })
        }

        @Test func recordsThenMatchesThenReportsChanges() async throws {
            let card = try await story("Card", "Card")
            let light = Variants(appearances: [.light])

            // A missing reference is recorded, and the test fails so it gets reviewed.
            try await withKnownIssue {
                try await SwiftBook.verify(
                    card, filePath: #filePath, variants: light, store: store, mode: .missing)
            } matching: {
                $0.comments.contains { $0.rawValue.contains("Recorded a new reference") }
            }

            try await SwiftBook.verify(
                card, filePath: #filePath, variants: light, store: store, mode: .never)

            // Replace the reference with a different render to simulate a changed view.
            let url = store.url(for: card.story.id, device: .mac, environment: RenderEnvironment())
            var dark = RenderEnvironment()
            dark.appearance = .dark
            try await MacRenderer.render(card.story, in: dark).pngData().write(to: url)
            try await withKnownIssue {
                try await SwiftBook.verify(
                    card, filePath: #filePath, variants: light, store: store, mode: .never)
            } matching: { issue in
                issue.comments.contains { comment in
                    comment.rawValue.contains("PreviewZoo/Card/Card (mac.light) doesn't match")
                        && comment.rawValue.contains("pixels changed")
                        && comment.rawValue.contains("SWIFTBOOK_RECORD=changed")
                }
            }
        }

        @Test func failsWhenAReferenceIsMissingInNeverMode() async throws {
            let card = try await story("Card", "Card")
            try await withKnownIssue {
                try await SwiftBook.verify(
                    card, filePath: #filePath, variants: Variants(appearances: [.light]),
                    store: store, mode: .never)
            } matching: {
                $0.comments.contains { $0.rawValue.contains("No reference") }
            }
        }
    }
#endif
