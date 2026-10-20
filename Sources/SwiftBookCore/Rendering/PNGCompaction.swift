import Foundation
import SwiftBookPNGFilters
import zlib

extension PNG {
    /// `png` re-encoded losslessly to be smaller, or `png` itself if that isn't smaller.
    ///
    /// ImageIO's PNG encoder compresses lightly. This chooses each row's filter by the smallest
    /// sum of absolute differences and deflates at zlib's highest level, and stores a fully
    /// opaque image as RGB rather than RGBA. Every other chunk, such as `tEXt`, `sRGB`, and
    /// `eXIf`, is kept byte for byte, so the image decodes to the same pixels with the same
    /// metadata. Only 8-bit, non-interlaced RGB and RGBA images are re-encoded; any other
    /// format is returned as is.
    static func compact(_ png: Data) throws -> Data {
        let bytes = [UInt8](png)
        let chunks = try chunks(png)
        guard let header = chunks.first, header.type == "IHDR", header.data.count == 13 else {
            throw Error(description: "PNG doesn't start with IHDR")
        }
        var fields = [UInt8](header.data)
        let width = fields[0..<4].reduce(0) { $0 << 8 | Int($1) }
        let height = fields[4..<8].reduce(0) { $0 << 8 | Int($1) }
        let (depth, color, interlace) = (fields[8], fields[9], fields[12])
        guard depth == 8, color == 2 || color == 6, interlace == 0, width > 0, height > 0 else {
            return png
        }
        var channels = color == 6 ? 4 : 3
        let compressed = chunks.filter { $0.type == "IDAT" }.reduce(into: Data()) {
            $0.append($1.data)
        }
        var pixels = unfilter(
            try inflate(compressed, size: height * (width * channels + 1)),
            width: width, height: height, channels: channels)
        // These chunks' contents depend on the color type, so keep it if any is present.
        let dependsOnColor: Set = ["tRNS", "bKGD", "sBIT", "PLTE", "hIST"]
        if channels == 4, !chunks.contains(where: { dependsOnColor.contains($0.type) }),
            isOpaque(pixels)
        {
            pixels = withoutAlpha(pixels)
            channels = 3
            fields[9] = 2
        }
        let data = try deflate(filter(pixels, width: width, height: height, channels: channels))

        var result = signature
        var wroteData = false
        for chunk in chunks {
            switch chunk.type {
            case "IHDR":
                result.append(Self.chunk(type: "IHDR", data: Data(fields)))
            case "IDAT":
                guard !wroteData else { continue }
                wroteData = true
                for start in stride(from: 0, to: data.count, by: 1 << 20) {
                    result.append(
                        Self.chunk(
                            type: "IDAT", data: data[start..<min(start + (1 << 20), data.count)]))
                }
            default:
                result.append(contentsOf: bytes[chunk.range])
            }
        }
        return result.count < png.count ? result : png
    }

    /// The image's rows, unfiltered, without their filter bytes.
    private static func unfilter(_ filtered: [UInt8], width: Int, height: Int, channels: Int)
        -> [UInt8]
    {
        let stride = width * channels
        var pixels = [UInt8](repeating: 0, count: stride * height)
        let zeros = [UInt8](repeating: 0, count: stride)
        filtered.withUnsafeBufferPointer { input in
            pixels.withUnsafeMutableBufferPointer { output in
                zeros.withUnsafeBufferPointer { zeros in
                    for y in 0..<height {
                        let row = output.baseAddress! + y * stride
                        row.update(from: input.baseAddress! + y * (stride + 1) + 1, count: stride)
                        swiftbook_png_unfilter_row(
                            input[y * (stride + 1)], row,
                            y > 0 ? UnsafePointer(row - stride) : zeros.baseAddress!, stride,
                            channels)
                    }
                }
            }
        }
        return pixels
    }

    /// The image's rows, each filtered with whichever filter leaves the smallest sum of absolute
    /// differences, after its filter byte.
    private static func filter(_ pixels: [UInt8], width: Int, height: Int, channels: Int)
        -> [UInt8]
    {
        let stride = width * channels
        var filtered = [UInt8](repeating: 0, count: (stride + 1) * height)
        var candidate = [UInt8](repeating: 0, count: stride)
        let zeros = [UInt8](repeating: 0, count: stride)
        pixels.withUnsafeBufferPointer { input in
            filtered.withUnsafeMutableBufferPointer { output in
                candidate.withUnsafeMutableBufferPointer { candidate in
                    zeros.withUnsafeBufferPointer { zeros in
                        for y in 0..<height {
                            let row = input.baseAddress! + y * stride
                            let above = y > 0 ? row - stride : zeros.baseAddress!
                            let out = output.baseAddress! + y * (stride + 1)
                            var best = (filter: UInt8(0), cost: Int.max)
                            for filter: UInt8 in 0...4 {
                                let cost = swiftbook_png_filter_row(
                                    filter, row, above, stride, channels, candidate.baseAddress!)
                                if Int(cost) < best.cost {
                                    best = (filter, Int(cost))
                                    (out + 1).update(from: candidate.baseAddress!, count: stride)
                                }
                            }
                            out.pointee = best.filter
                        }
                    }
                }
            }
        }
        return filtered
    }

    private static func isOpaque(_ rgba: [UInt8]) -> Bool {
        swiftbook_png_is_opaque(rgba, rgba.count / 4) != 0
    }

    private static func withoutAlpha(_ rgba: [UInt8]) -> [UInt8] {
        var rgb = [UInt8](repeating: 0, count: rgba.count / 4 * 3)
        swiftbook_png_drop_alpha(rgba, rgba.count / 4, &rgb)
        return rgb
    }

    /// `data`, zlib-decompressed, which must be `size` bytes.
    private static func inflate(_ data: Data, size: Int) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: size)
        var length = uLongf(size)
        let status = data.withUnsafeBytes { input in
            output.withUnsafeMutableBufferPointer { output in
                uncompress(
                    output.baseAddress, &length,
                    input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count))
            }
        }
        guard status == Z_OK, length == size else {
            throw Error(description: "PNG image data doesn't decompress to its size")
        }
        return output
    }

    /// `bytes`, zlib-compressed at the highest level.
    private static func deflate(_ bytes: [UInt8]) throws -> Data {
        var output = [UInt8](repeating: 0, count: Int(compressBound(uLong(bytes.count))))
        var length = uLongf(output.count)
        let status = bytes.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { output in
                compress2(
                    output.baseAddress, &length, input.baseAddress, uLong(bytes.count),
                    Z_BEST_COMPRESSION)
            }
        }
        guard status == Z_OK else { throw Error(description: "can't compress PNG image data") }
        return Data(output.prefix(Int(length)))
    }
}
