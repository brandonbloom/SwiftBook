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

        @Test func reportsRerecordedReferencesWithoutFailing() async throws {
            let card = try await story("Card", "Card")
            let light = Variants(appearances: [.light])
            let url = store.url(for: card.story.id, device: .mac, environment: RenderEnvironment())
            var dark = RenderEnvironment()
            dark.appearance = .dark
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await MacRenderer.render(card.story, in: dark).pngData().write(to: url)

            // Known issues include warnings, so this checks the warning's text and severity.
            try await withKnownIssue {
                try await SwiftBook.verify(
                    card, filePath: #filePath, variants: light, store: store, mode: .changed)
            } matching: { issue in
                issue.severity == .warning
                    && issue.comments.contains { comment in
                        comment.rawValue.contains("Re-recorded PreviewZoo/Card/Card (mac.light)")
                            && comment.rawValue.contains("pixels changed")
                            && comment.rawValue.contains("Diff image:")
                    }
            }
            try await SwiftBook.verify(
                card, filePath: #filePath, variants: light, store: store, mode: .never)
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
