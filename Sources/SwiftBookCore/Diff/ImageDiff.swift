import CoreGraphics
import Foundation

/// The difference between an expected and an actual image.
public struct ImageDiff: @unchecked Sendable {
    // Unchecked: CGImage is immutable.

    /// What counts as a change.
    public struct Tolerance: Hashable, Sendable {
        /// The largest CIEDE2000 difference treated as a match. 1 is about the limit of perception.
        public var deltaE: Double = 1
        /// The fraction of pixels allowed to change.
        public var changedPixelRatio: Double = 0
        /// Whether pixels that look like shifted anti-aliasing are ignored.
        public var ignoresAntialiasing = true
        /// A few faint changed pixels are noise, not a change: GPU-rendered materials such as
        /// Liquid Glass can settle a pixel or two differently from run to run. A diff with at most
        /// `noisePixels` changed pixels, none differing by more than `noiseDeltaE`, matches.
        public var noisePixels = 10
        public var noiseDeltaE: Double = 3

        public init() {}
    }

    public let expectedSize: CGSize
    public let actualSize: CGSize
    /// Pixels differing by more than the tolerance, excluding anti-aliasing.
    public let changedPixels: Int
    /// Differing pixels attributed to anti-aliasing and ignored.
    public let antialiasedPixels: Int
    /// The largest CIEDE2000 difference of any pixel, whether or not it counted as changed.
    public let maxDeltaE: Double
    /// The largest CIEDE2000 difference of a changed pixel.
    public let maxChangedDeltaE: Double
    /// The smallest rectangle, in pixels, containing every changed pixel.
    public let changedBounds: CGRect?
    /// Expected faded to gray, with changed pixels red and anti-aliased pixels yellow. `nil` when
    /// the images are identical or their sizes differ.
    public let image: CGImage?
    public let tolerance: Tolerance

    public var sizesMatch: Bool { expectedSize == actualSize }
    public var isIdentical: Bool { sizesMatch && maxDeltaE == 0 }

    /// Changed pixels as a fraction of all pixels; 1 when the sizes differ.
    public var changedPixelRatio: Double {
        guard sizesMatch else { return 1 }
        let total = expectedSize.width * expectedSize.height
        return total == 0 ? 0 : Double(changedPixels) / total
    }

    /// Whether the actual image matches the expected one within the tolerance.
    public var matches: Bool {
        sizesMatch
            && (changedPixelRatio <= tolerance.changedPixelRatio || isNoise)
    }

    /// Whether the only changes are a few faint pixels, within the tolerance's noise floor.
    public var isNoise: Bool {
        sizesMatch && changedPixels <= tolerance.noisePixels
            && maxChangedDeltaE <= tolerance.noiseDeltaE
    }

    /// ``image`` as PNG data.
    public func pngData() throws -> Data? {
        try image.map { try PNG.encode($0, text: [:]) }
    }

    /// Compares two images pixel by pixel, perceptually.
    public static func compare(
        expected: CGImage, actual: CGImage, tolerance: Tolerance = Tolerance()
    ) throws
        -> ImageDiff
    {
        let expectedSize = CGSize(width: expected.width, height: expected.height)
        let actualSize = CGSize(width: actual.width, height: actual.height)
        guard expectedSize == actualSize else {
            return ImageDiff(
                expectedSize: expectedSize, actualSize: actualSize, changedPixels: 0,
                antialiasedPixels: 0,
                maxDeltaE: .infinity, maxChangedDeltaE: .infinity, changedBounds: nil, image: nil,
                tolerance: tolerance)
        }
        let a = try Bitmap(expected)
        let b = try Bitmap(actual)
        let width = a.width
        if a.pixels == b.pixels {
            return ImageDiff(
                expectedSize: expectedSize, actualSize: actualSize, changedPixels: 0,
                antialiasedPixels: 0,
                maxDeltaE: 0, maxChangedDeltaE: 0, changedBounds: nil, image: nil,
                tolerance: tolerance)
        }
        var output = Bitmap(width: width, height: a.height, pixels: faded(a))

        var changed = 0
        var antialiased = 0
        var maxDeltaE = 0.0
        var maxChangedDeltaE = 0.0
        var deltaEs: [UInt64: Double] = [:]
        var bounds = (minX: Int.max, minY: Int.max, maxX: Int.min, maxY: Int.min)
        a.pixels.withUnsafeBufferPointer { pa in
            b.pixels.withUnsafeBufferPointer { pb in
                for index in 0..<(width * a.height) {
                    let offset = index * 4
                    if pa[offset] == pb[offset], pa[offset + 1] == pb[offset + 1],
                        pa[offset + 2] == pb[offset + 2],
                        pa[offset + 3] == pb[offset + 3]
                    {
                        continue
                    }
                    // UI has few distinct colors, so most differing pixels repeat a pair already seen.
                    let pair = UInt64(a.word(index)) << 32 | UInt64(b.word(index))
                    let deltaE: Double
                    if let known = deltaEs[pair] {
                        deltaE = known
                    } else {
                        deltaE = ColorMath.deltaE2000(a.rgb(index), b.rgb(index))
                        deltaEs[pair] = deltaE
                    }
                    maxDeltaE = max(maxDeltaE, deltaE)
                    guard deltaE > tolerance.deltaE else { continue }
                    let (x, y) = (index % width, index / width)
                    if tolerance.ignoresAntialiasing, Antialiasing.isAntialiased(x: x, y: y, a, b) {
                        antialiased += 1
                        output.paint(index, red: 255, green: 220, blue: 0)
                    } else {
                        changed += 1
                        maxChangedDeltaE = max(maxChangedDeltaE, deltaE)
                        output.paint(index, red: 255, green: 0, blue: 0)
                        bounds = (
                            min(bounds.minX, x), min(bounds.minY, y), max(bounds.maxX, x),
                            max(bounds.maxY, y)
                        )
                    }
                }
            }
        }
        let changedBounds =
            changed == 0
            ? nil
            : CGRect(
                x: bounds.minX, y: bounds.minY, width: bounds.maxX - bounds.minX + 1,
                height: bounds.maxY - bounds.minY + 1)
        return ImageDiff(
            expectedSize: expectedSize, actualSize: actualSize, changedPixels: changed,
            antialiasedPixels: antialiased,
            maxDeltaE: maxDeltaE, maxChangedDeltaE: maxChangedDeltaE, changedBounds: changedBounds,
            image: output.image(),
            tolerance: tolerance)
    }

    /// `bitmap` as faint grayscale over white, the backdrop for highlighted changes.
    private static func faded(_ bitmap: Bitmap) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: bitmap.pixels.count)
        for index in 0..<(bitmap.width * bitmap.height) {
            let gray = UInt8(255 - (255 - ColorMath.luma(bitmap.rgb(index))) * 0.1)
            pixels[index * 4] = gray
            pixels[index * 4 + 1] = gray
            pixels[index * 4 + 2] = gray
        }
        return pixels
    }
}

extension Bitmap {
    /// The pixel at `index` as one 32-bit value.
    @inline(__always) fileprivate func word(_ index: Int) -> UInt32 {
        let offset = index * 4
        return UInt32(pixels[offset]) << 24 | UInt32(pixels[offset + 1]) << 16 | UInt32(
            pixels[offset + 2]) << 8
            | UInt32(pixels[offset + 3])
    }

    fileprivate mutating func paint(_ index: Int, red: UInt8, green: UInt8, blue: UInt8) {
        pixels[index * 4] = red
        pixels[index * 4 + 1] = green
        pixels[index * 4 + 2] = blue
        pixels[index * 4 + 3] = 255
    }
}
