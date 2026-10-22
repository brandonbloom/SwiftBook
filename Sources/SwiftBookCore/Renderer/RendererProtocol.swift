import Foundation
import SwiftUI

/// The protocol between SwiftBook's tools and a renderer process, which links the user's code.
///
/// Messages are JSON objects, one per line. The renderer first sends a ``RendererHello``, then
/// answers each ``RendererRequest`` with a ``RendererResponse`` carrying the same `id`, in order.
public enum RendererProtocol {
    /// Bumped whenever a message changes incompatibly.
    public static let version = 1
}

/// The renderer's first message.
public struct RendererHello: Codable, Hashable, Sendable {
    public var protocolVersion: Int
    public var swiftBookVersion: String
    /// Such as `macOS`.
    public var platform: String
    /// The version of the OS the renderer runs on, such as `27.0.1`.
    public var osVersion: String?

    public init(
        protocolVersion: Int, swiftBookVersion: String, platform: String, osVersion: String? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.swiftBookVersion = swiftBookVersion
        self.platform = platform
        self.osVersion = osVersion
    }
}

/// What a render should record of the code it runs, for `swiftbook test --changed`.
public struct RenderRecording: Codable, Hashable, Sendable {
    /// The snapshot's identifier, stable from run to run.
    public var test: String
    /// What the snapshot's shared contexts are recorded under, such as the device.
    public var scope: String

    public init(test: String, scope: String) {
        self.test = test
        self.scope = scope
    }
}

/// A request to a renderer.
public struct RendererRequest: Codable, Hashable, Sendable {
    public enum Method: String, Codable, Sendable {
        /// List every story. With `check`, also build each one's view and report failures.
        case list
        /// Render `story` in `environment`.
        case render
        /// Show `story` in `environment` in a window of its own, live and interactive. macOS
        /// only.
        case open
        /// List the windows `open` showed that are still open.
        case windows
        /// Exit.
        case shutdown
    }

    public var id: Int
    public var method: Method
    public var check: Bool?
    /// The story ID, as `Module/Group/Name`.
    public var story: String?
    public var environment: RenderEnvironment?
    /// For `render`: what to record of the code the render runs, if anything.
    public var recording: RenderRecording?

    public init(
        id: Int, method: Method, check: Bool? = nil, story: String? = nil,
        environment: RenderEnvironment? = nil, recording: RenderRecording? = nil
    ) {
        self.id = id
        self.method = method
        self.check = check
        self.story = story
        self.environment = environment
        self.recording = recording
    }
}

/// A renderer's answer to the request with the same `id`.
public struct RendererResponse: Codable, Hashable, Sendable {
    public var id: Int
    /// For `list`.
    public var stories: [StoryInfo]?
    /// For `render`: the snapshot as PNG, with its metadata.
    public var png: Data?
    /// For `render`: where the snapshot has Liquid Glass, in pixels, if anywhere.
    public var glassRegions: [ImageDiff.PixelRect]?
    /// For `windows`.
    public var windows: [RendererWindow]?
    /// Why the request failed.
    public var error: String?

    public init(
        id: Int, stories: [StoryInfo]? = nil, png: Data? = nil,
        glassRegions: [ImageDiff.PixelRect]? = nil, windows: [RendererWindow]? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.stories = stories
        self.png = png
        self.glassRegions = glassRegions
        self.windows = windows
        self.error = error
    }
}

/// A rendered snapshot as it crosses the protocol.
public struct RenderedImage: Sendable {
    /// The snapshot as PNG, with its metadata.
    public let png: Data
    /// Where it has Liquid Glass, in pixels.
    public let glassRegions: [ImageDiff.PixelRect]

    public init(png: Data, glassRegions: [ImageDiff.PixelRect] = []) {
        self.png = png
        self.glassRegions = glassRegions
    }
}

/// A story's interactive window, as `open` showed it.
public struct RendererWindow: Codable, Hashable, Sendable {
    /// The story ID, as `Module/Group/Name`.
    public var story: String
    public var environment: RenderEnvironment

    public init(story: String, environment: RenderEnvironment) {
        self.story = story
        self.environment = environment
    }
}

/// A story as a renderer lists it.
public struct StoryInfo: Codable, Hashable, Sendable {
    public var module: String
    public var group: String
    public var name: String
    public var fileID: String?
    public var line: Int?
    /// Why the story's view couldn't be built, from a `list` with `check`.
    public var error: String?
    /// Whether the package's ``SwiftBookConfiguration`` leaves the story out of snapshot tests.
    /// Optional so that a renderer's response needn't mention it.
    public var excluded: Bool?

    /// Whether `swiftbook test` checks the story.
    public var isTested: Bool { excluded != true }

    /// `Module/Group/Name`.
    public var id: StoryID { StoryID(module: module, group: group, name: name) }

    public init(id: StoryID, fileID: String? = nil, line: Int? = nil, error: String? = nil) {
        module = id.module
        group = id.group
        name = id.name
        self.fileID = fileID
        self.line = line
        self.error = error
    }

    public init(story: Story, error: String? = nil) {
        module = story.id.module
        group = story.id.group
        name = story.id.name
        fileID = story.fileID
        line = story.line
        self.error = error
    }
}

extension RenderEnvironment: Codable {
    private enum CodingKeys: String, CodingKey {
        case appearance, scale, locale, timeZone, dynamicTypeSize, layoutDirection
        case deviceWidth, deviceHeight
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decode(Appearance.self, forKey: .appearance)
        scale = try container.decode(Double.self, forKey: .scale)
        localeIdentifier = try container.decode(String.self, forKey: .locale)
        timeZoneIdentifier = try container.decode(String.self, forKey: .timeZone)
        let size = try container.decode(String.self, forKey: .dynamicTypeSize)
        guard let dynamicTypeSize = DynamicTypeSize.allCases.first(where: { "\($0)" == size })
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .dynamicTypeSize, in: container,
                debugDescription: "no Dynamic Type size \(size)")
        }
        self.dynamicTypeSize = dynamicTypeSize
        layoutDirection =
            try container.decode(String.self, forKey: .layoutDirection) == "rightToLeft"
            ? .rightToLeft : .leftToRight
        deviceWidth = try container.decode(Double.self, forKey: .deviceWidth)
        deviceHeight = try container.decode(Double.self, forKey: .deviceHeight)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(scale, forKey: .scale)
        try container.encode(localeIdentifier, forKey: .locale)
        try container.encode(timeZoneIdentifier, forKey: .timeZone)
        try container.encode("\(dynamicTypeSize)", forKey: .dynamicTypeSize)
        try container.encode(
            layoutDirection == .rightToLeft ? "rightToLeft" : "leftToRight",
            forKey: .layoutDirection)
        try container.encode(deviceWidth, forKey: .deviceWidth)
        try container.encode(deviceHeight, forKey: .deviceHeight)
    }
}

extension RenderEnvironment.Appearance: Codable {}
