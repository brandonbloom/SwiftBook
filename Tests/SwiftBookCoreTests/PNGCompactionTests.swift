import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import SwiftBookCore

@Suite struct PNGCompactionTests {
    static let zoo = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/PreviewZoo/Snapshots/PreviewZoo", directoryHint: .isDirectory)

    /// The decoded pixels of `png`, as SwiftBook compares them.
    func pixels(_ png: Data) throws -> [UInt8] {
        try Bitmap(SnapshotStore.image(png, at: "png")).pixels
    }

    @Test(arguments: ["Card/Card/mac.light.png", "Card/Card/iphone.dark.png"])
    func shrinksReferencesWithoutChangingThem(reference: String) throws {
        let original = try Data(contentsOf: Self.zoo.appending(path: reference))
        try #require(!GitLFS.isPointer(original), "run git lfs pull")
        let compact = try PNG.compact(original)
        #expect(compact.count < original.count * 3 / 4)
        #expect(try pixels(compact) == pixels(original))
        #expect(try PNG.text(in: compact) == PNG.text(in: original))
        #expect(try PNG.compact(compact) == compact)
    }

    @Test func keepsAlphaThatIsntOpaque() throws {
        var rgba = [UInt8](repeating: 200, count: 8 * 8 * 4)
        rgba[3] = 100
        let image = try #require(Bitmap(width: 8, height: 8, pixels: rgba).image())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        let compact = try PNG.compact(data as Data)
        #expect(try pixels(compact) == pixels(data as Data))
        // Still RGBA: color type 6 in IHDR.
        #expect(compact[25] == 6)
    }
}
