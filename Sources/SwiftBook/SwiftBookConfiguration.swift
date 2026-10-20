// What a package's own code declares for SwiftBook. This module has no dependencies besides
// SwiftUI, so app libraries can link it.

import SwiftUI

/// Settings for every story SwiftBook renders from a package: in snapshot tests, in
/// `swiftbook test` on simulators, in the viewer, and in interactive windows.
///
/// Declare one conforming type in any library whose previews SwiftBook renders, typically the
/// one with your design system. SwiftBook finds it the way it finds previews, so it needs no
/// registration:
///
/// ```swift
/// import SwiftBook
///
/// struct Snapshots: SwiftBookConfiguration {
///     static var tint: Color? { Color("AccentColor", bundle: .module) }
/// }
/// ```
///
/// Declare at most one per package. If there are several, SwiftBook uses the first by
/// module-qualified type name and warns.
public protocol SwiftBookConfiguration {
    /// The tint around every story, as `.tint(_:)` applies it, or `nil` for the system's.
    ///
    /// Previews render outside your app, so they don't get its global accent color: the
    /// `AccentColor` an app target names with `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME`.
    /// Set this to the same color so controls in snapshots look as they do in the app. A color
    /// from an asset catalog keeps its light and dark appearances.
    @MainActor static var tint: Color? { get }

    /// Stories to leave out of snapshot tests, as `Module/Group/Name`, on every device: under
    /// `swift test` and in `swiftbook test`. They still render in the viewer and in Xcode.
    ///
    /// Use it for a preview that can't render the same way twice, such as a map that loads its
    /// tiles from the network. For one that draws in stages, ``settling`` may be enough.
    @MainActor static var excluded: Set<String> { get }

    /// How long each listed story, as `Module/Group/Name`, must hold still before it's
    /// captured, on every device.
    ///
    /// SwiftBook captures a render once two captures in a row match. A view that draws in
    /// stages can hold still between them: a `PDFView` draws a blurry page first and sharp tiles
    /// later. A hold of a second or so waits out such stages. Other stories don't wait.
    @MainActor static var settling: [String: Duration] { get }
}

extension SwiftBookConfiguration {
    public static var tint: Color? { nil }
    public static var excluded: Set<String> { [] }
    public static var settling: [String: Duration] { [:] }
}
