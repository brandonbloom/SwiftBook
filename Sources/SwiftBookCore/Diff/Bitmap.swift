import CoreGraphics

/// An image's pixels as 8-bit sRGB RGBA, premultiplied, for comparison.
struct Bitmap {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else {
            throw DiffError(description: "can't read a \(image.width)×\(image.height) image")
        }
    }

    /// The pixel at `index` composited over white, as RGB.
    @inline(__always) func rgb(_ index: Int) -> (Double, Double, Double) {
        let offset = index * 4
        // Premultiplied over white: c + (255 - alpha).
        let missing = 255 - Double(pixels[offset + 3])
        return (
            Double(pixels[offset]) + missing, Double(pixels[offset + 1]) + missing,
            Double(pixels[offset + 2]) + missing
        )
    }

    @inline(__always) func samePixel(_ a: Int, _ b: Int) -> Bool {
        let a = a * 4
        let b = b * 4
        return pixels[a] == pixels[b] && pixels[a + 1] == pixels[b + 1]
            && pixels[a + 2] == pixels[b + 2]
            && pixels[a + 3] == pixels[b + 3]
    }

    func image() -> CGImage? {
        let data = CFDataCreate(nil, pixels, pixels.count)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
    }
}

struct DiffError: Error, CustomStringConvertible {
    let description: String
}
