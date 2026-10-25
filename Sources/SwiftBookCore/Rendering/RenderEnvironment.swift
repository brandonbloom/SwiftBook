import SwiftUI

/// Everything about a rendering that would otherwise come from the machine doing it.
///
/// Renders pin each of these, so a reference recorded on one Mac matches a render on another.
package struct RenderEnvironment: Hashable, Sendable {
    package enum Appearance: String, Hashable, Sendable, CaseIterable {
        case light, dark
    }

    package var appearance: Appearance = .light
    /// Pixels per point.
    package var scale: Double = 2
    package var localeIdentifier = "en_US"
    package var timeZoneIdentifier = "UTC"
    package var dynamicTypeSize: DynamicTypeSize = .large
    package var layoutDirection: LayoutDirection = .leftToRight
    /// The canvas for stories with the device layout, in points.
    package var deviceWidth: Double = 800
    package var deviceHeight: Double = 600

    package init() {}

    /// The defaults for `device`: its pinned model's scale and screen size, in points. The Mac
    /// has no screen of its own, so it gets a fixed canvas.
    package static func standard(for device: Device) -> RenderEnvironment {
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
    /// Applies the environment's SwiftUI values and the package's tint, and disables animations.
    @MainActor func pinned(to environment: RenderEnvironment) -> some View {
        live(in: environment)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }

    /// Applies the environment's SwiftUI values and the package's tint, leaving animations on,
    /// for interacting with.
    @MainActor func live(in environment: RenderEnvironment) -> some View {
        self
            .tint(ProjectConfiguration.tint)
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
package struct RenderError: Error, CustomStringConvertible, Sendable {
    package let story: StoryID
    package let problem: String

    package var description: String { "Couldn't render \(story): \(problem)" }
}
