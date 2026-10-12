import Foundation
import Testing

@testable import SwiftBookCore

@Suite struct FlakeFinderTests {
    /// A 10×10 gray PNG, with one pixel `shade` at `dot`, if any.
    func png(dot: Int? = nil, shade: UInt8 = 0) throws -> Data {
        var pixels = [UInt8](repeating: 128, count: 10 * 10 * 4)
        for index in 0..<100 { pixels[index * 4 + 3] = 255 }
        if let dot { pixels.replaceSubrange(dot * 4..<dot * 4 + 3, with: [shade, shade, shade]) }
        return try PNG.encode(Bitmap(width: 10, height: 10, pixels: pixels).image()!, text: [:])
    }

    @Test func showsWhereFaintVariantsDiffer() throws {
        var finder = FlakeFinder()
        for run in 0..<10 {
            finder.add(try png(dot: run < 8 ? nil : 42, shade: 129), for: "A (mac.light)")
        }
        let flake = try #require(try finder.flakes().first)
        // Too faint for a comparison to fail on…
        #expect(!flake.wouldFail)
        #expect(flake.differences[0].changedBounds == nil)
        // …but every differing pixel is still found and shown.
        #expect(flake.exactDifferences[0].changedBounds == CGRect(x: 2, y: 4, width: 1, height: 1))
        let diff = try SnapshotStore.image(try #require(try flake.differenceImage(0)), at: "diff")
        #expect((diff.width, diff.height) == (10, 10))
        // The 10×10 image, enlarged 8 times, three times over with gaps between.
        let closeUp = try SnapshotStore.image(try #require(try flake.closeUp(0)), at: "close-up")
        #expect((closeUp.width, closeUp.height) == (80 * 3 + 16, 80))
    }

    @Test func passesOverSnapshotsThatRenderOneWay() throws {
        var finder = FlakeFinder()
        for _ in 0..<5 { finder.add(try png(), for: "A (iphone.light)") }
        // Failing every run is consistent too: that's a failure, not a flake.
        for _ in 0..<5 { finder.addFailure("boom", for: "B (iphone.light)") }
        #expect(try finder.flakes().isEmpty)
    }

    @Test func groupsRendersIntoVariantsMostCommonFirst() throws {
        var finder = FlakeFinder()
        for run in 0..<10 { finder.add(try png(dot: run < 7 ? nil : 42), for: "A (iphone.dark)") }
        let flakes = try finder.flakes()
        #expect(flakes.map(\.subject) == ["A (iphone.dark)"])
        #expect(flakes[0].variants.map(\.count) == [7, 3])
        #expect(flakes[0].differences.count == 1)
        #expect(flakes[0].differences[0].changedPixels == 1)
        #expect(flakes[0].exactDifferences.map(\.changedPixels) == [1])
        // A black pixel on gray is far past the noise floor: a comparison would fail.
        #expect(!flakes[0].differences[0].matches)
        #expect(flakes[0].differences[0].changedBounds == CGRect(x: 2, y: 4, width: 1, height: 1))
    }

    @Test func countsRendersThatSometimesFail() throws {
        var finder = FlakeFinder()
        for _ in 0..<8 { finder.add(try png(), for: "A (mac.light)") }
        finder.addFailure("took longer than 30 seconds", for: "A (mac.light)")
        finder.addFailure("crashed", for: "A (mac.light)")
        let flakes = try finder.flakes()
        #expect(flakes.count == 1)
        #expect(flakes[0].variants.count == 1)
        #expect(flakes[0].failures == 2)
        #expect(flakes[0].failure == "took longer than 30 seconds")
    }
}
