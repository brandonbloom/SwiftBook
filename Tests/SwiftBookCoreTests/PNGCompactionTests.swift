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

    /// `image` as ImageIO encodes it, as SwiftBook wrote references before 0.3.
    func imageIOEncoding(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test(arguments: ["Card/Card/mac.light.png", "Card/Card/iphone.dark.png"])
    func shrinksReferencesWithoutChangingThem(reference: String) throws {
        let recorded = try Data(contentsOf: Self.zoo.appending(path: reference))
        try #require(!GitLFS.isPointer(recorded), "run git lfs pull")
        // The zoo's references are already compact.
        #expect(try PNG.compact(recorded) == recorded)

        let original = try imageIOEncoding(SnapshotStore.image(recorded, at: reference))
        let compact = try PNG.compact(original)
        #expect(compact.count < original.count * 3 / 4)
        #expect(try pixels(compact) == pixels(original))
        #expect(try PNG.compact(compact) == compact)
    }

    @Test func keepsAlphaThatIsntOpaque() throws {
        var rgba = [UInt8](repeating: 200, count: 8 * 8 * 4)
        rgba[3] = 100
        let image = try #require(Bitmap(width: 8, height: 8, pixels: rgba).image())
        let png = try imageIOEncoding(image)
        let compact = try PNG.compact(png)
        #expect(try pixels(compact) == pixels(png))
        // Still RGBA: color type 6 in IHDR.
        #expect(compact[25] == 6)
    }
}
