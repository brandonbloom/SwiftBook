#if os(macOS)
    import AppKit
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookViewer

    /// A history whose basis has fixed changed files and references.
    struct FakeHistory: HistorySource {
        var basis = ViewerBasis.uncommitted
        var paths: [String] = []
        /// References by story ID; stories without one are new.
        var references: [String: Data] = [:]

        func defaultBasis() -> ViewerBasis { basis }

        func changes(against basis: ViewerBasis) throws -> (revision: String, paths: [String]) {
            ("abc123", paths)
        }

        func reference(
            for story: StoryID, appearance: RenderEnvironment.Appearance, at revision: String
        ) throws -> Data? {
            references[story.description]
        }
    }

    @MainActor @Suite struct HistoryTests {
        static func png(_ color: NSColor) -> Data {
            let image = NSImage(size: CGSize(width: 40, height: 20), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
            return NSBitmapImageRep(data: image.tiffRepresentation!)!
                .representation(using: .png, properties: [:])!
        }

        @Test func matchesStoriesToChangedSourceFiles() {
            let story = StoryInfo(
                id: StoryID(module: "FBFUI", group: "Card", name: "Card"),
                fileID: "FBFUI/Card.swift")
            #expect(History.sourceChanged(story, in: ["Sources/FBFUI/Views/Card.swift"]))
            #expect(!History.sourceChanged(story, in: ["Sources/Other/Card.swift"]))
            #expect(!History.sourceChanged(story, in: ["Sources/FBFUI/Cards.swift"]))
            #expect(
                !History.sourceChanged(StoryInfo(id: story.id), in: ["Sources/FBFUI/Card.swift"]))
        }

        @Test func comparesRendersWithReferences() {
            let blue = Self.png(.systemBlue)
            #expect(History.imageStatus(render: blue, reference: blue) == .unchanged)
            #expect(History.imageStatus(render: blue, reference: Self.png(.systemRed)) == .changed)
            #expect(History.imageStatus(render: blue, reference: nil) == .new)
        }

        /// Waits until nothing is rendering and statuses have settled.
        func settle(_ model: ViewerModel) async {
            for _ in 0..<300 {
                try? await Task.sleep(for: .milliseconds(10))
                if model.pending.isEmpty, model.basisRevision != nil,
                    !model.statuses.values.contains(.pending) || model.statuses.isEmpty
                {
                    try? await Task.sleep(for: .milliseconds(50))
                    return
                }
            }
        }

        @Test func marksSourceChangesThenImageChanges() async {
            let renderer = FakeRenderer(["M/A/Same", "M/B/Edited", "M/C/Fresh"])
            // The fake renders solid blue; one reference matches, one doesn't.
            let history = FakeHistory(
                paths: ["Sources/M/B.swift"],
                references: [
                    "M/A/Same": FakeRenderer.png, "M/B/Edited": Self.png(.systemRed),
                ])
            let model = ViewerModel(package: URL(filePath: "/tmp/Package")) { _ in
                renderer
            } openHistory: { _ in
                history
            }
            await model.start()
            await settle(model)
            #expect(model.basis == .uncommitted)
            #expect(model.basisRevision == "abc123")
            #expect(model.statuses[ViewerModelTests.story("M/A/Same")] == .unchanged)
            #expect(model.statuses[ViewerModelTests.story("M/B/Edited")] == .changed)
            #expect(model.statuses[ViewerModelTests.story("M/C/Fresh")] == .new)

            model.showsChangedOnly = true
            #expect(model.visibleTree.flatMap { $0.children ?? [] }.map(\.title) == ["B", "C"])
            model.showsChangedOnly = false
            model.searchText = "fresh"
            #expect(model.visibleTree.flatMap { $0.children ?? [] }.map(\.title) == ["C"])
        }

        @Test func comparesTheWorkingTreeWithTheBasis() async throws {
            let renderer = FakeRenderer(["M/A/Same", "M/B/Edited", "M/C/Fresh"])
            let history = FakeHistory(references: [
                "M/A/Same": FakeRenderer.png, "M/B/Edited": Self.png(.systemRed),
            ])
            let model = ViewerModel(package: URL(filePath: "/tmp/Package")) { _ in
                renderer
            } openHistory: { _ in
                history
            }
            await model.start()
            await settle(model)
            model.compareMode = .grid
            model.compareDimension = .revision
            #expect(
                model.cells.map(\.title) == [
                    "Uncommitted changes · abc123", "Working tree", "Difference",
                ])

            /// The selection's comparison, once it's in.
            func comparison() async -> ViewerModel.Comparison? {
                for _ in 0..<300 {
                    if let comparison = model.comparison(of: model.cells[1]) { return comparison }
                    try? await Task.sleep(for: .milliseconds(10))
                }
                return nil
            }

            let same = try #require(await comparison())
            #expect(same.matches && same.maxDeltaE == 0)
            #expect(model.state(of: model.cells[2]) == .empty("Identical"))
            guard case .image = model.state(of: model.cells[0]) else {
                Issue.record("no reference image")
                return
            }

            model.selection = ViewerModelTests.story("M/B/Edited")
            let edited = try #require(await comparison())
            #expect(!edited.matches && edited.changedPixelRatio == 1)
            guard case .image = model.state(of: model.cells[2]) else {
                Issue.record("no difference image")
                return
            }

            model.selection = ViewerModelTests.story("M/C/Fresh")
            await settle(model)
            #expect(model.state(of: model.cells[0]) == .empty("No reference at the basis"))
            #expect(model.state(of: model.cells[2]) == .empty("No reference at the basis"))

            model.layoutDirection = .rightToLeft
            #expect(
                model.state(of: model.cells[0])
                    == .empty("References are recorded left to right only"))
        }

        @Test func readsTheZoosReferencesFromGit() throws {
            let zoo = RendererSupervisorTests.faultZoo.deletingLastPathComponent()
                .appending(path: "PreviewZoo", directoryHint: .isDirectory)
            let history = try History(package: zoo)
            let (revision, _) = try history.changes(against: .uncommitted)
            let card = try history.reference(
                for: StoryID(module: "PreviewZoo", group: "Card", name: "Card"), appearance: .light,
                at: revision)
            #expect(card?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
            #expect(
                try history.reference(
                    for: StoryID(module: "PreviewZoo", group: "Card", name: "Nope"),
                    appearance: .light, at: revision) == nil)
        }
    }
#endif
