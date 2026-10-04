import SwiftUI

/// Everything about a rendering that would otherwise come from the machine doing it.
///
/// Renders pin each of these, so a reference recorded on one Mac matches a render on another.
public struct RenderEnvironment: Hashable, Sendable {
    public enum Appearance: String, Hashable, Sendable, CaseIterable {
        case light, dark
    }

    public var appearance: Appearance = .light
    /// Pixels per point.
    public var scale: Double = 2
    public var localeIdentifier = "en_US"
    public var timeZoneIdentifier = "UTC"
    public var dynamicTypeSize: DynamicTypeSize = .large
    public var layoutDirection: LayoutDirection = .leftToRight
    /// The canvas for stories with the device layout, in points.
    public var deviceWidth: Double = 800
    public var deviceHeight: Double = 600

    public init() {}

    /// The defaults for `device`: its pinned model's scale and screen size, in points. The Mac
    /// has no screen of its own, so it gets a fixed canvas.
    public static func standard(for device: Device) -> RenderEnvironment {
        var environment = RenderEnvironment()
        switch device {
        case .mac, .catalyst:
            break
        case .iphone:
            // iPhone 17 Pro.
            environment.scale = 3
            environment.deviceWidth = 402
            environment.deviceHeight = 874
        case .ipad:
            // 11-inch iPad Pro.
            environment.deviceWidth = 834
            environment.deviceHeight = 1210
        case .tv:
            // Apple TV 4K.
            environment.deviceWidth = 1920
            environment.deviceHeight = 1080
        }
        return environment
    }
}

extension View {
    /// Applies the environment's SwiftUI values and disables animations.
    func pinned(to environment: RenderEnvironment) -> some View {
        live(in: environment)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }

    /// Applies the environment's SwiftUI values, leaving animations on, for interacting with.
    func live(in environment: RenderEnvironment) -> some View {
        self
            .environment(\.colorScheme, environment.appearance == .dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: environment.localeIdentifier))
            .environment(\.timeZone, TimeZone(identifier: environment.timeZoneIdentifier) ?? .gmt)
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.displayScale, environment.scale)
    }
}

/// A story couldn't be rendered.
public struct RenderError: Error, CustomStringConvertible, Sendable {
    public let story: StoryID
    public let problem: String

    public var description: String { "Couldn't render \(story): \(problem)" }
}
