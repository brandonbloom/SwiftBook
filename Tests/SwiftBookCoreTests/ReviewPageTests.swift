import Foundation
import Testing

@testable import SwiftBookCore

@Suite struct ReviewPageTests {
    let directory = URL(filePath: "/tmp/project/.build/swiftbook/review")

    func entry(_ story: String, _ variant: String, _ kind: ReviewEntry.Kind) -> ReviewEntry {
        ReviewEntry(
            story: story, variant: variant, kind: kind, message: "\(story) <changed>",
            images: [
                .init(role: "reference", path: "/tmp/project/Snapshots/\(story)/\(variant).png")
            ])
    }

    @Test func linksImagesRelativeToThePage() {
        #expect(
            ReviewPage.relativePath(
                to: URL(filePath: "/tmp/project/Snapshots/M/G/S/mac.light.png"), from: directory)
                == "../../../Snapshots/M/G/S/mac.light.png")
        #expect(
            ReviewPage.relativePath(
                to: URL(filePath: "/tmp/project/.build/swiftbook/failures/a.png"), from: directory)
                == "../failures/a.png")
    }

    @Test func groupsStoriesAndSummarizes() throws {
        let html = ReviewPage.html(
            [
                entry("M/Card/Card", "mac.dark", .failed),
                entry("M/Card/Card", "mac.light", .failed),
                entry("M/Badge/Badge", "mac.light", .new),
            ], directory: directory)
        #expect(html.contains("1 new · 2 failed"))
        // Groups are sorted, and each story's variants are in name order.
        let badge = try #require(html.range(of: "<h2>M/Badge</h2>"))
        let card = try #require(html.range(of: "<h2>M/Card</h2>"))
        #expect(badge.lowerBound < card.lowerBound)
        let dark = try #require(html.range(of: "</span> mac.dark"))
        let light = try #require(
            html.range(of: "</span> mac.light", range: card.upperBound..<html.endIndex))
        #expect(dark.lowerBound < light.lowerBound)
        // Messages are escaped.
        #expect(html.contains("M/Card/Card &lt;changed&gt;"))
        #expect(html.contains("src=\"../../../Snapshots/M/Card/Card/mac.dark.png\""))
    }

    func changed(_ story: String, _ variant: String, x: Int, y: Int, width: Int, height: Int)
        -> ReviewEntry
    {
        var entry = entry(story, variant, .changed)
        entry.images.append(.init(role: "diff", path: "/tmp/diff/\(story)/\(variant).png"))
        entry.region = .init(x: x, y: y, width: width, height: height)
        return entry
    }

    @Test func measuresHowMuchRegionsOverlap() {
        let a = ImageDiff.PixelRect(x: 0, y: 0, width: 10, height: 10)
        #expect(ReviewPage.overlap(a, a) == 1)
        #expect(ReviewPage.overlap(a, .init(x: 5, y: 0, width: 10, height: 10)) == 50.0 / 150)
        #expect(ReviewPage.overlap(a, .init(x: 10, y: 0, width: 10, height: 10)) == 0)
    }

    @Test func groupsChangesToTheSameRegionAcrossStories() throws {
        // A new sidebar row: the same region changed in three stories, light and dark.
        var entries = ["M/A/A", "M/B/B", "M/C/C"].flatMap { story in
            ["mac.dark", "mac.light"].map {
                changed(story, $0, x: 0, y: 100, width: 200, height: 40)
            }
        }
        // Nearly the same region still counts; elsewhere, or in too few stories, doesn't.
        entries.append(changed("M/D/D", "mac.light", x: 0, y: 102, width: 200, height: 40))
        entries.append(changed("M/E/E", "mac.light", x: 300, y: 0, width: 50, height: 50))
        entries.append(changed("M/F/F", "mac.light", x: 300, y: 0, width: 50, height: 50))
        entries.append(entry("M/G/G", "mac.light", .new))

        let (shared, rest) = ReviewPage.sharedChanges(entries)
        #expect(
            shared.map { $0.map(\.story) } == [
                ["M/A/A", "M/A/A", "M/B/B", "M/B/B", "M/C/C", "M/C/C", "M/D/D"]
            ])
        #expect(rest.map(\.story) == ["M/E/E", "M/F/F", "M/G/G"])

        let html = ReviewPage.html(entries, directory: directory)
        let group = try #require(html.range(of: "<h2>Shared changes</h2>"))
        #expect(
            html.contains("7 references in 4 stories changed within 200×40 at (0, 100)"))
        // The first in full, the rest as diff images, before the stories with other changes.
        #expect(html.contains("</span> M/A/A mac.dark"))
        #expect(html.contains("diff/M/D/D/mac.light.png"))
        #expect(!html.contains("Snapshots/M/D/D/mac.light.png"))
        let others = try #require(html.range(of: "<h2>M/E</h2>"))
        #expect(group.upperBound < others.lowerBound)
    }

    @Test func inlinesImagesToMakeOneFile() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "ReviewPageTests-\(UUID())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let png = directory.appending(path: "reference.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: png)
        let entry = ReviewEntry(
            story: "M/G/S", variant: "mac.light", kind: .failed, message: "",
            images: [.init(role: "reference", path: png.path)])
        let page = directory.appending(path: "page.html")
        try ReviewPage.write([entry], to: page, inlineImages: true)
        let html = try String(contentsOf: page, encoding: .utf8)
        #expect(html.contains("src=\"data:image/png;base64,iVBORw==\""))
        #expect(!html.contains("reference.png"))
    }

    @Test func saysWhenTheresNothingToReview() {
        #expect(ReviewPage.html([], directory: directory).contains("Nothing to review."))
    }
}
