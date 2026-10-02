import SwiftBookCore
import Testing

@Suite struct StoryIDTests {
    @Test func namedStoriesKeepTheirNames() {
        let ids = StoryID.assign([("M", "Card", "Card"), ("M", "Card", "Card (dark)")])
        #expect(ids.map(\.name) == ["Card", "Card (dark)"])
    }

    @Test func unnamedStoriesAreNumberedInOrder() {
        let ids = StoryID.assign([
            ("M", "Card", nil), ("M", "Card", "Named"), ("M", "Card", nil), ("M", "Card", nil),
        ])
        #expect(ids.map(\.name) == ["Preview", "Named", "Preview 2", "Preview 3"])
    }

    @Test func duplicateNamesAreNumberedInOrder() {
        let ids = StoryID.assign([("M", "Edge", "Duplicate"), ("M", "Edge", "Duplicate")])
        #expect(ids.map(\.name) == ["Duplicate", "Duplicate 2"])
    }

    @Test func numberingSkipsNamesAlreadyTaken() {
        let ids = StoryID.assign([("M", "F", "Preview 2"), ("M", "F", nil), ("M", "F", nil)])
        #expect(ids.map(\.name) == ["Preview 2", "Preview", "Preview 3"])
    }

    @Test func groupsAndModulesAreNumberedIndependently() {
        let ids = StoryID.assign([("M", "A", nil), ("M", "B", nil), ("N", "A", nil)])
        #expect(ids.map(\.name) == ["Preview", "Preview", "Preview"])
        #expect(ids.map(\.description) == ["M/A/Preview", "M/B/Preview", "N/A/Preview"])
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
