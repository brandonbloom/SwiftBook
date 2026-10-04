import CoreGraphics
import Foundation
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
