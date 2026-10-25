#if os(macOS)
    import Foundation

    /// The process's scroller style, which renders pin to overlay.
    ///
    /// With "Show scroll bars: Automatically", macOS switches to legacy scrollers whenever it
    /// thinks a mouse is attached, as when a Mac is docked. Legacy scrollers take about 15 points
    /// from every list, table, and scroll view, so text rewraps and layouts move. AppKit reads the
    /// style once per process, so it's pinned before the first render, in the argument domain,
    /// where it outranks the user's setting.
    package enum ScrollerStyle {
        /// Pins overlay scrollers for this process, keeping the argument domain's other entries.
        /// Takes effect only if AppKit hasn't read the style yet.
        package static func pinOverlay() { _ = pinned }

        /// The `AppleShowScrollBars` value that means overlay scrollers.
        static let overlay = "WhenScrolling"

        private static let pinned: Void = {
            let defaults = UserDefaults.standard
            var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            arguments["AppleShowScrollBars"] = overlay
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        }()
    }
#endif
