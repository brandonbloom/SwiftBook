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

    @Test func saysWhenTheresNothingToReview() {
        #expect(ReviewPage.html([], directory: directory).contains("Nothing to review."))
    }
}
