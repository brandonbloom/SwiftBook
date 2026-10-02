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
}

extension View {
    /// Applies the environment's SwiftUI values and disables animations.
    func pinned(to environment: RenderEnvironment) -> some View {
        self
            .environment(\.colorScheme, environment.appearance == .dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: environment.localeIdentifier))
            .environment(\.timeZone, TimeZone(identifier: environment.timeZoneIdentifier) ?? .gmt)
            .environment(\.calendar, Calendar(identifier: .gregorian))
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.layoutDirection, environment.layoutDirection)
            .environment(\.displayScale, environment.scale)
            .transaction { transaction in
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
    }
}
