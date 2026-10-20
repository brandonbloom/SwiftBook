import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A rendered story: its image and how it was rendered.
public struct Snapshot: @unchecked Sendable {
    // Unchecked: CGImage is immutable.

    public let story: StoryID
    public let device: Device
    public let environment: RenderEnvironment
    public let image: CGImage
    public let metadata: SnapshotMetadata
    /// Where the image has Liquid Glass, in pixels, for comparing it (``ImageDiff/compare(expected:actual:tolerance:glass:)``).
    /// Not saved: references stay exactly the image.
    public var glassRegions: [ImageDiff.PixelRect] = []
    /// The PNG the snapshot arrived as, if it came from a renderer: ``pngData()`` without
    /// encoding it again.
    private let encoded: Data?

    init(
        story: StoryID, device: Device, environment: RenderEnvironment, image: CGImage,
        metadata: SnapshotMetadata, encoded: Data? = nil
    ) {
        self.story = story
        self.device = device
        self.environment = environment
        self.image = image
        self.metadata = metadata
        self.encoded = encoded
    }

    /// A snapshot a renderer sent as PNG, with its metadata.
    public init(png: Data, story: StoryID, device: Device, environment: RenderEnvironment) throws {
        guard let metadata = try SnapshotMetadata.read(fromPNG: png) else {
            throw StorageError(description: "the render of \(story) has no SwiftBook metadata")
        }
        self.init(
            story: story, device: device, environment: environment,
            image: try SnapshotStore.image(png, at: story.description), metadata: metadata,
            encoded: png)
    }

    /// The image as a PNG, with ``metadata`` in a `SwiftBook` text chunk.
    public func pngData() throws -> Data {
        try encoded ?? PNG.encode(image, text: ["SwiftBook": try metadata.json()])
    }
}

/// How a snapshot was rendered. Stored in its PNG, so a mismatch on verify can be explained.
public struct SnapshotMetadata: Codable, Hashable, Sendable {
    /// The story, as `Module/Group/Name`.
    public var story: String
    public var device: String
    public var platform: String
    public var osVersion: String
    public var scale: Double
    public var appearance: String
    public var locale: String
    public var timeZone: String
    public var dynamicTypeSize: String
    public var layoutDirection: String
    public var swiftBookVersion: String
    /// The ``CaptureMethod``, `nil` in references recorded before capture methods existed.
    public var capture: String?
    /// The package's tint (``ProjectConfiguration``) as rendered, as `#RRGGBB`, or `nil` for the
    /// system's.
    public var tint: String?

    func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }

    /// Reads the metadata from a PNG written by ``Snapshot/pngData()``.
    public static func read(fromPNG data: Data) throws -> SnapshotMetadata? {
        guard let json = try PNG.text(in: data)["SwiftBook"] else { return nil }
        return try JSONDecoder().decode(SnapshotMetadata.self, from: Data(json.utf8))
    }
}

public enum SwiftBookInfo {
    /// Recorded in snapshot metadata.
    public static let version = "0.1.0"
}

/// PNG encoding with `tEXt` chunks, which ImageIO can't write for arbitrary keys.
enum PNG {
    struct Error: Swift.Error, CustomStringConvertible {
        let description: String
    }

    static func encode(_ image: CGImage, text: [String: String]) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { throw Error(description: "can't create a PNG encoder") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw Error(description: "can't encode PNG")
        }
        return try insert(text: text, into: data as Data)
    }

    /// The `tEXt` chunks in a PNG.
    static func text(in png: Data) throws -> [String: String] {
        var text: [String: String] = [:]
        for chunk in try chunks(png) where chunk.type == "tEXt" {
            guard let separator = chunk.data.firstIndex(of: 0) else { continue }
            let key = String(decoding: chunk.data[..<separator], as: UTF8.self)
            text[key] = String(decoding: chunk.data[(separator + 1)...], as: UTF8.self)
        }
        return text
    }

    static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    struct Chunk {
        let type: String
        let data: Data
        /// The chunk's full encoding: length, type, data, and CRC.
        let range: Range<Int>
    }

    static func chunks(_ png: Data) throws -> [Chunk] {
        let bytes = [UInt8](png)
        guard bytes.starts(with: signature) else { throw Error(description: "not a PNG") }
        var chunks: [Chunk] = []
        var offset = signature.count
        while offset + 12 <= bytes.count {
            let length = bytes[offset..<offset + 4].reduce(0) { $0 << 8 | Int($1) }
            let end = offset + 12 + length
            guard end <= bytes.count else { throw Error(description: "truncated PNG chunk") }
            let type = String(decoding: bytes[offset + 4..<offset + 8], as: UTF8.self)
            chunks.append(
                Chunk(
                    type: type, data: Data(bytes[offset + 8..<offset + 8 + length]),
                    range: offset..<end))
            offset = end
        }
        return chunks
    }

    /// Inserts `tEXt` chunks, sorted by key, right after `IHDR`.
    private static func insert(text: [String: String], into png: Data) throws -> Data {
        guard let header = try chunks(png).first, header.type == "IHDR" else {
            throw Error(description: "PNG doesn't start with IHDR")
        }
        var result = png.prefix(header.range.upperBound)
        for (key, value) in text.sorted(by: { $0.key < $1.key }) {
            result.append(chunk(type: "tEXt", data: Data(key.utf8) + [0] + Data(value.utf8)))
        }
        result.append(png.suffix(from: header.range.upperBound))
        return Data(result)
    }

    static func chunk(type: String, data: Data) -> Data {
        let typeAndData = Data(type.utf8) + data
        return bigEndian(UInt32(data.count)) + typeAndData + bigEndian(crc32(typeAndData))
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    }

    private static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crcTable[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}
