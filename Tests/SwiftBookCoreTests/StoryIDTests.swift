import Foundation
import Swiftpothesis
import Testing

@testable import SwiftBookCore

@Suite struct StoryIDTests {
    @Test func namedStoriesKeepTheirNames() {
        let ids = StoryID.assign([("M", "Card", "Card"), ("M", "Card", "Card (dark)")])
        #expect(ids.map(\.name) == ["Card", "Card (dark)"])
    }

    @Test func unnamedStoriesTakeTheGroupNameNumberedInOrder() {
        let ids = StoryID.assign([
            ("M", "Card", nil), ("M", "Card", "Named"), ("M", "Card", nil), ("M", "Card", nil),
        ])
        #expect(ids.map(\.name) == ["Card", "Named", "Card 2", "Card 3"])
    }

    @Test func unnamedStoriesShareNumberingWithAStoryNamedLikeTheGroup() {
        // Xcode labels these "Card Line 30", "Card Line 34", and "Card Line 38".
        let ids = StoryID.assign([("M", "Card", nil), ("M", "Card", nil), ("M", "Card", "Card")])
        #expect(ids.map(\.name) == ["Card", "Card 2", "Card 3"])
    }

    @Test func duplicateNamesAreNumberedInOrder() {
        let ids = StoryID.assign([("M", "Edge", "Duplicate"), ("M", "Edge", "Duplicate")])
        #expect(ids.map(\.name) == ["Duplicate", "Duplicate 2"])
    }

    @Test func numberingSkipsNamesAlreadyTaken() {
        let ids = StoryID.assign([("M", "F", "F 2"), ("M", "F", nil), ("M", "F", nil)])
        #expect(ids.map(\.name) == ["F 2", "F", "F 3"])
    }

    @Test func namesThatWouldShareAReferenceAreNumbered() {
        let ids = StoryID.assign([
            ("M", "G", "Dark"), ("M", "G", "dark"), ("M", "G", "Row:"), ("M", "G", "Row?"),
            ("M", "G", "Card."), ("M", "G", "Card"), ("M", "G", "Caf\u{E9}"),
            ("M", "G", "Cafe\u{301}"),
        ])
        #expect(
            ids.map(\.name) == [
                "Dark", "dark 2", "Row:", "Row? 2", "Card.", "Card 2", "Caf\u{E9}",
                "Cafe\u{301} 2",
            ])
    }

    @Test func groupsThatWouldShareADirectoryNumberTheirStories() {
        let ids = StoryID.assign([("M", "Row", nil), ("M", "row", nil)])
        #expect(ids.map(\.description) == ["M/Row/Row", "M/row/row 2"])
    }

    /// Short names from characters that collide in file names: case, characters that become `_`,
    /// trailing dots and spaces, and composed and decomposed accents.
    static var names: some Generator<String> {
        String.arbitrary(
            element(of: Array("aA_:?. e\u{E9}\u{301}".unicodeScalars)), count: 0...3)
    }

    /// Stories in a few groups, some unnamed.
    static var stories: some Generator<[(module: String, group: String, displayName: String?)]> {
        [(module: String, group: String, displayName: String?)].arbitrary(
            zip(element(of: ["M", "m"]), element(of: ["G", "g", "G:"]), String?.arbitrary(names))
                .map { (module: $0, group: $1, displayName: $2) },
            count: 0...8)
    }

    @Test func storiesNeverShareAReference() async {
        let store = SnapshotStore(root: URL(filePath: "/Snapshots", directoryHint: .isDirectory))
        await forAll(Self.stories) { stories in
            let paths = StoryID.assign(stories).map {
                store.url(for: $0, device: .mac, environment: RenderEnvironment()).path
                    .decomposedStringWithCanonicalMapping.lowercased()
            }
            #expect(Set(paths).count == paths.count)
        }
    }

    @Test func storiesWhoseReferencesWouldntCollideKeepTheirIDs() async {
        // Numbering only exact repeats, as assign did before it considered file names.
        func exact(_ stories: [(module: String, group: String, displayName: String?)])
            -> [StoryID]
        {
            var taken: Set<StoryID> = []
            return stories.map { story in
                let base = story.displayName ?? story.group
                var candidate = StoryID(module: story.module, group: story.group, name: base)
                var ordinal = 1
                while taken.contains(candidate) {
                    ordinal += 1
                    candidate = StoryID(
                        module: story.module, group: story.group, name: "\(base) \(ordinal)")
                }
                taken.insert(candidate)
                return candidate
            }
        }
        await forAll(Self.stories) { stories in
            let before = exact(stories)
            try assume(Set(before.map(\.pathKey)).count == before.count)
            #expect(StoryID.assign(stories) == before)
        }
    }

    @Test func groupsAndModulesAreNumberedIndependently() {
        let ids = StoryID.assign([("M", "A", nil), ("M", "B", nil), ("N", "A", nil)])
        #expect(ids.map(\.description) == ["M/A/A", "M/B/B", "N/A/A"])
    }

    @Test(arguments: [
        ("Zoo/Card.swift", "Card"),
        ("Zoo/Card.Extensions.swift", "Card.Extensions"),
        ("Zoo/NoExtension", "NoExtension"),
        ("Zoo/.hidden", ".hidden"),
    ])
    func groupIsTheFileStem(fileID: String, group: String) {
        #expect(StoryID.group(forFileID: fileID) == group)
    }
}
