import CoreGraphics
import Foundation

extension FlakeFinder.Flake {
    /// Where variant `index` (0 for the second variant, and so on) differs from the most common
    /// one: every differing pixel red on the faded render, inside a blue box. `nil` when they
    /// don't differ or their sizes do.
    package func differenceImage(_ index: Int) throws -> Data? {
        let exact = exactDifferences[index]
        guard let image = exact.image, let bounds = exact.changedBounds else { return nil }
        var bitmap = try Bitmap(image)
        let line = max(2, min(bitmap.width, bitmap.height) / 300)
        bitmap.stroke(bounds.insetBy(dx: CGFloat(-2 * line), dy: CGFloat(-2 * line)), width: line)
        return try bitmap.image().map { try PNG.encode($0, text: [:]) }
    }

    /// The difference between the most common variant and variant `index`, enlarged: the most
    /// common one, the other, and the differing pixels, side by side. `nil` when they don't
    /// differ or their sizes do.
    package func closeUp(_ index: Int) throws -> Data? {
        let exact = exactDifferences[index]
        guard let diff = exact.image, let bounds = exact.changedBounds else { return nil }
        let first = try Bitmap(SnapshotStore.image(variants[0].png, at: subject))
        let other = try Bitmap(SnapshotStore.image(variants[index + 1].png, at: subject))
        let marked = try Bitmap(diff)
        // At least 48 pixels around the difference, for context, within the image.
        let side = { (length: CGFloat) in max(48, length + 32) }
        let region = CGRect(
            x: bounds.midX - side(bounds.width) / 2, y: bounds.midY - side(bounds.height) / 2,
            width: side(bounds.width), height: side(bounds.height)
        ).integral.intersection(CGRect(x: 0, y: 0, width: first.width, height: first.height))
        let scale = max(1, min(8, 320 / Int(max(region.width, region.height))))
        let (width, height) = (Int(region.width) * scale, Int(region.height) * scale)
        let gap = 8
        var output = Bitmap(
            width: width * 3 + gap * 2, height: height,
            pixels: [UInt8](repeating: 255, count: (width * 3 + gap * 2) * height * 4))
        for (panel, source) in [first, other, marked].enumerated() {
            for y in 0..<height {
                for x in 0..<width {
                    let from =
                        (Int(region.minY) + y / scale) * source.width + Int(region.minX) + x / scale
                    let to = (y * output.width + panel * (width + gap) + x) * 4
                    output.pixels.replaceSubrange(
                        to..<to + 4, with: source.pixels[from * 4..<from * 4 + 4])
                }
            }
        }
        return try output.image().map { try PNG.encode($0, text: [:]) }
    }
}

extension Bitmap {
    /// Outlines `rect`, clipped to the image, in opaque blue.
    fileprivate mutating func stroke(_ rect: CGRect, width line: Int) {
        let (minX, minY) = (max(Int(rect.minX), 0), max(Int(rect.minY), 0))
        let (maxX, maxY) = (min(Int(rect.maxX), width) - 1, min(Int(rect.maxY), height) - 1)
        guard minX <= maxX, minY <= maxY else { return }
        for y in minY...maxY {
            for x in minX...maxX
            where x < minX + line || x > maxX - line || y < minY + line || y > maxY - line {
                let offset = (y * width + x) * 4
                pixels.replaceSubrange(offset..<offset + 4, with: [0, 90, 255, 255])
            }
        }
    }
}
