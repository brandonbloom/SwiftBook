import CoreGraphics
import Foundation
import Swiftpothesis
import Testing

@testable import SwiftBookCore

@Suite struct ImageDiffTests {
    /// An opaque image filled with one gray, with optional pixels painted, rows top to bottom.
    func image(
        width: Int = 20, height: Int = 20, gray: UInt8 = 255,
        paint: [(x: Int, y: Int, rgb: [UInt8])] = []
    )
        -> CGImage
    {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in 0..<(width * height) {
            pixels.replaceSubrange(index * 4..<index * 4 + 4, with: [gray, gray, gray, 255])
        }
        for pixel in paint {
            let offset = (pixel.y * width + pixel.x) * 4
            pixels.replaceSubrange(offset..<offset + 3, with: pixel.rgb)
        }
        return Bitmap(width: width, height: height, pixels: pixels).image()!
    }

    /// A gray disc, anti-aliased, on white.
    func disc(centerX: Double, size: Int = 40) -> CGImage {
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fillEllipse(
            in: CGRect(x: centerX - 12, y: Double(size) / 2 - 12, width: 24, height: 24))
        return context.makeImage()!
    }

    /// Dark glass as the render server draws it: dithered (every other pixel's channels a few
    /// levels apart, in a checkerboard) or banded (flat). The two states differ by more than
    /// ΔE 1 at half the pixels. `block` paints a real change: 10×10 pixels 40 levels lighter.
    func glass(dithered: Bool, block: (x: Int, y: Int)? = nil) -> CGImage {
        let (width, height) = (120, 40)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let shift: UInt8 = dithered && (x + y) % 2 == 0 ? 3 : 0
                var rgb: [UInt8] = [20 + shift, 24, 40 - shift]
                if let block, (block.x..<block.x + 10).contains(x),
                    (block.y..<block.y + 10).contains(y)
                {
                    rgb = rgb.map { $0 + 40 }
                }
                pixels.replaceSubrange((y * width + x) * 4..<(y * width + x) * 4 + 3, with: rgb)
            }
        }
        return Bitmap(width: width, height: height, pixels: pixels).image()!
    }

    @Test func ignoresGlassNoiseOnlyInsideGlass() throws {
        let dithered = glass(dithered: true)
        let banded = glass(dithered: false)
        let everywhere = [ImageDiff.PixelRect(x: 0, y: 0, width: 120, height: 40)]

        // Outside glass, banding is a change like any other.
        let exact = try ImageDiff.compare(expected: dithered, actual: banded)
        #expect(!exact.matches)
        #expect(exact.changedPixels == 2_400)

        // Inside glass, it's noise: it still shows in the diff image, but doesn't count.
        let inGlass = try ImageDiff.compare(expected: dithered, actual: banded, glass: everywhere)
        #expect(inGlass.matches)
        #expect(inGlass.changedPixels == 0)
        #expect(inGlass.glassNoisePixels == 2_400)
        #expect(inGlass.image != nil)
        #expect(try inGlass.pngData() == exact.pngData())

        // Glass covers only where it is.
        let leftHalf = [ImageDiff.PixelRect(x: 0, y: 0, width: 60, height: 40)]
        let partly = try ImageDiff.compare(expected: dithered, actual: banded, glass: leftHalf)
        #expect(!partly.matches)
        #expect(partly.changedPixels == 1_200)

        // A real change inside glass still counts.
        let changed = try ImageDiff.compare(
            expected: dithered, actual: glass(dithered: false, block: (50, 15)), glass: everywhere)
        #expect(!changed.matches)
        #expect(changed.changedPixels >= 80)
    }

    /// A small opaque image and a copy with a few pixels repainted.
    struct ImagePair: Sendable, CustomStringConvertible {
        var width: Int
        var height: Int
        var expected: [UInt8]
        var actual: [UInt8]

        var expectedImage: CGImage {
            Bitmap(width: width, height: height, pixels: expected).image()!
        }
        var actualImage: CGImage { Bitmap(width: width, height: height, pixels: actual).image()! }

        /// The indices of the pixels that differ.
        var differing: [Int] {
            (0..<width * height).filter {
                expected[$0 * 4..<$0 * 4 + 4] != actual[$0 * 4..<$0 * 4 + 4]
            }
        }

        var description: String {
            "\(width)×\(height), \(differing.count) differing at \(differing)"
        }
    }

    /// Pairs that shrink toward smaller images, plainer colors, and fewer repainted pixels.
    /// Colors come mostly from a few, so flat regions and anti-aliasing-like edges are common.
    static var pairs: some Generator<ImagePair> {
        zip(Int.arbitrary(in: 1...6), Int.arbitrary(in: 1...6)).map { ($0, $1) }.flatMap { size in
            let (width, height) = size
            let color = oneOf(
                element(
                    of: [[255, 255, 255], [0, 0, 0], [128, 128, 128], [255, 0, 0]] as [[UInt8]]),
                [UInt8].arbitrary(UInt8.arbitrary, count: 3...3))
            let edit = Swiftpothesis.zip(Int.arbitrary(in: 0...(width * height - 1)), color)
            return Swiftpothesis.zip(
                [[UInt8]].arbitrary(color, count: (width * height)...(width * height)),
                [(Int, [UInt8])].arbitrary(edit, count: 0...8)
            ).map { colors, edits in
                let expected: [UInt8] = colors.flatMap { $0 + [255] }
                var actual = expected
                for (index, rgb) in edits {
                    actual.replaceSubrange(index * 4..<index * 4 + 3, with: rgb)
                }
                return ImagePair(width: width, height: height, expected: expected, actual: actual)
            }
        }
    }

    @Test func everyImageMatchesItself() async {
        await forAll(Self.pairs) { pair in
            let diff = try ImageDiff.compare(expected: pair.actualImage, actual: pair.actualImage)
            #expect(diff.isIdentical)
            #expect(diff.matches)
            #expect(diff.changedPixels == 0)
            #expect(diff.image == nil)
        }
    }

    @Test func onlyDifferingPixelsCount() async {
        await forAll(Self.pairs) { pair in
            let diff = try ImageDiff.compare(expected: pair.expectedImage, actual: pair.actualImage)
            let differing = pair.differing
            #expect(diff.changedPixels + diff.antialiasedPixels <= differing.count)
            #expect(diff.isIdentical == differing.isEmpty)
            // Changes lie within the pixels that differ.
            if let bounds = diff.changedBounds {
                let xs = differing.map { $0 % pair.width }
                let ys = differing.map { $0 / pair.width }
                #expect(bounds.minX >= CGFloat(xs.min()!) && bounds.maxX <= CGFloat(xs.max()! + 1))
                #expect(bounds.minY >= CGFloat(ys.min()!) && bounds.maxY <= CGFloat(ys.max()! + 1))
            }
        }
    }

    @Test func comparisonIsSymmetric() async {
        await forAll(Self.pairs) { pair in
            let forward = try ImageDiff.compare(
                expected: pair.expectedImage, actual: pair.actualImage)
            let backward = try ImageDiff.compare(
                expected: pair.actualImage, actual: pair.expectedImage)
            #expect(forward.changedPixels == backward.changedPixels)
            #expect(forward.antialiasedPixels == backward.antialiasedPixels)
            #expect(forward.changedBounds == backward.changedBounds)
        }
    }

    @Test func aLooserToleranceNeverAddsChanges() async {
        await forAll(Self.pairs, Double.arbitrary(in: 0...30), Double.arbitrary(in: 0...30)) {
            pair, a, b in
            var strict = ImageDiff.Tolerance()
            strict.deltaE = min(a, b)
            var loose = strict
            loose.deltaE = max(a, b)
            let (expected, actual) = (pair.expectedImage, pair.actualImage)
            let strictDiff = try ImageDiff.compare(
                expected: expected, actual: actual, tolerance: strict)
            let looseDiff = try ImageDiff.compare(
                expected: expected, actual: actual, tolerance: loose)
            #expect(looseDiff.changedPixels <= strictDiff.changedPixels)
            #expect(!strictDiff.matches || looseDiff.matches)
        }
    }

    @Test func glassOnlyTurnsChangesIntoNoise() async {
        let rects = zip(
            Int.arbitrary(in: 0...6), Int.arbitrary(in: 0...6), Int.arbitrary(in: 0...6),
            Int.arbitrary(in: 0...6)
        ).map { ImageDiff.PixelRect(x: $0, y: $1, width: $2, height: $3) }
        await forAll(Self.pairs, [ImageDiff.PixelRect].arbitrary(rects, count: 0...3)) {
            pair, glass in
            let (expected, actual) = (pair.expectedImage, pair.actualImage)
            let plain = try ImageDiff.compare(expected: expected, actual: actual)
            let glassy = try ImageDiff.compare(expected: expected, actual: actual, glass: glass)
            #expect(glassy.changedPixels + glassy.glassNoisePixels == plain.changedPixels)
            #expect(glassy.antialiasedPixels == plain.antialiasedPixels)
            #expect(!plain.matches || glassy.matches)
        }
    }

    @Test func colorDifferenceIsADistance() async {
        let rgb = zip(
            Double.arbitrary(in: 0...255), Double.arbitrary(in: 0...255),
            Double.arbitrary(in: 0...255)
        ).map { ($0, $1, $2) }
        await forAll(rgb, rgb) { a, b in
            #expect(ColorMath.deltaE2000(a, a) == 0)
            let forward = ColorMath.deltaE2000(a, b)
            #expect(forward.isFinite && forward >= 0)
            #expect(abs(forward - ColorMath.deltaE2000(b, a)) < 1e-9)
        }
    }

    @Test func identicalImagesMatchExactly() throws {
        let diff = try ImageDiff.compare(expected: image(), actual: image())
        #expect(diff.isIdentical)
        #expect(diff.matches)
        #expect(diff.changedPixels == 0)
        #expect(diff.changedBounds == nil)
    }

    @Test func findsASinglePixelChange() throws {
        let diff = try ImageDiff.compare(
            expected: image(), actual: image(paint: [(5, 7, [255, 0, 0])]))
        #expect(diff.changedPixels == 1)
        #expect(diff.changedBounds == CGRect(x: 5, y: 7, width: 1, height: 1))
        #expect(!diff.matches)
        #expect(diff.maxDeltaE > 30)
    }

    @Test func toleratesImperceptibleColorShifts() throws {
        let diff = try ImageDiff.compare(expected: image(gray: 128), actual: image(gray: 129))
        #expect(diff.changedPixels == 0)
        #expect(diff.maxDeltaE > 0)
        #expect(diff.maxDeltaE < 1)
        #expect(diff.matches)
        #expect(!diff.isIdentical)
    }

    @Test func countsPerceptibleColorShifts() throws {
        let diff = try ImageDiff.compare(expected: image(gray: 128), actual: image(gray: 160))
        #expect(diff.changedPixelRatio == 1)
        #expect(diff.changedBounds == CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    @Test func reportsSizeChanges() throws {
        let diff = try ImageDiff.compare(expected: image(width: 20), actual: image(width: 21))
        #expect(!diff.sizesMatch)
        #expect(!diff.matches)
        #expect(diff.changedPixelRatio == 1)
        #expect(diff.image == nil)
    }

    @Test func ignoresShiftedAntialiasing() throws {
        // A subpixel shift changes only the edge pixels' coverage.
        let diff = try ImageDiff.compare(expected: disc(centerX: 20), actual: disc(centerX: 20.3))
        #expect(diff.antialiasedPixels > 0)
        #expect(diff.changedPixels == 0)
        var strict = ImageDiff.Tolerance()
        strict.ignoresAntialiasing = false
        #expect(
            try ImageDiff.compare(
                expected: disc(centerX: 20), actual: disc(centerX: 20.3), tolerance: strict
            )
            .changedPixels > 0)
    }

    @Test func treatsAFewFaintPixelsAsNoise() throws {
        // A gray a little off: past the perceptual threshold, under the noise threshold.
        let faint: [UInt8] = [128, 128, 133]
        let few = try ImageDiff.compare(
            expected: image(gray: 128), actual: image(gray: 128, paint: [(3, 3, faint)]))
        #expect(few.changedPixels == 1)
        #expect(few.maxChangedDeltaE > 1 && few.maxChangedDeltaE <= 3)
        #expect(few.isNoise)
        #expect(few.matches)

        // Many faint pixels are a change, and so is one strong one.
        let many = try ImageDiff.compare(
            expected: image(gray: 128),
            actual: image(gray: 128, paint: (0..<11).map { ($0, 0, faint) }))
        #expect(!many.matches)
        let strong = try ImageDiff.compare(
            expected: image(gray: 128), actual: image(gray: 128, paint: [(3, 3, [255, 0, 0])]))
        #expect(!strong.matches)

        var strict = ImageDiff.Tolerance()
        strict.noisePixels = 0
        #expect(
            try !ImageDiff.compare(
                expected: image(gray: 128), actual: image(gray: 128, paint: [(3, 3, faint)]),
                tolerance: strict
            ).matches)
    }

    @Test func allowsAToleratedRatioOfChangedPixels() throws {
        var tolerance = ImageDiff.Tolerance()
        tolerance.changedPixelRatio = 0.01
        let diff = try ImageDiff.compare(
            expected: image(width: 100, height: 100),
            actual: image(width: 100, height: 100, paint: [(1, 1, [0, 0, 0])]),
            tolerance: tolerance)
        #expect(diff.changedPixels == 1)
        #expect(diff.matches)
    }

    @Test func highlightsChangesInTheDiffImage() throws {
        let diff = try ImageDiff.compare(
            expected: image(), actual: image(paint: [(5, 7, [0, 0, 255])]))
        let pixels = try Bitmap(try #require(diff.image)).pixels
        let changed = (7 * 20 + 5) * 4
        #expect(Array(pixels[changed..<changed + 4]) == [255, 0, 0, 255])
        // Unchanged white stays white.
        #expect(Array(pixels[0..<4]) == [255, 255, 255, 255])
    }

    /// Writes each golden case's expected, actual, and diff images into `$SWIFTBOOK_ARTIFACTS`
    /// for people to look at.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"] != nil))
    func writesArtifacts() throws {
        let directory = URL(filePath: ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cases: [(name: String, expected: CGImage, actual: CGImage)] = [
            ("identical", image(), image()),
            ("one pixel", image(), image(paint: [(5, 7, [255, 0, 0])])),
            ("imperceptible shift", image(gray: 128), image(gray: 129)),
            ("perceptible shift", image(gray: 128), image(gray: 160)),
            ("antialiasing shift", disc(centerX: 20), disc(centerX: 20.3)),
            ("size change", image(width: 20), image(width: 21)),
        ]
        for golden in cases {
            let diff = try ImageDiff.compare(expected: golden.expected, actual: golden.actual)
            let images = ["expected": golden.expected, "actual": golden.actual, "diff": diff.image]
            for (role, image) in images {
                guard let image else { continue }
                try PNG.encode(image, text: [:]).write(
                    to: directory.appending(path: "\(golden.name)--\(role).png"))
            }
            let summary = """
                changed \(diff.changedPixels), antialiased \(diff.antialiasedPixels), \
                max ΔE \(diff.maxDeltaE), matches \(diff.matches)
                """
            try Data(summary.utf8).write(to: directory.appending(path: "\(golden.name).txt"))
        }
    }

    @Test func comparesAFullCanvasChangeQuickly() throws {
        let expected = image(width: 1600, height: 1200, gray: 100)
        let actual = image(width: 1600, height: 1200, gray: 200)
        // CPU time on this thread, so tests running in parallel can't slow the measurement.
        func cpuTime() -> Duration {
            var time = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
            return .seconds(time.tv_sec) + .nanoseconds(time.tv_nsec)
        }
        let start = cpuTime()
        let diff = try ImageDiff.compare(expected: expected, actual: actual)
        let elapsed = cpuTime() - start
        #expect(diff.changedPixelRatio == 1)
        // About 50 ms optimized; unoptimized builds are around 80 times slower.
        #if DEBUG
            #expect(elapsed < .seconds(10))
        #else
            #expect(elapsed < .milliseconds(250))
        #endif
    }
}
