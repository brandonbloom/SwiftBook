import SwiftBookCore
import Testing

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
