#if os(macOS)
    import AppKit
    import SwiftUI

    /// A story couldn't be rendered.
    public struct RenderError: Error, CustomStringConvertible, Sendable {
        public let story: StoryID
        public let problem: String

        public var description: String { "Couldn't render \(story): \(problem)" }
    }

    /// The process-wide time zone, which Foundation's date formatting reads.
    ///
    /// Setting `NSTimeZone.default` isn't enough: format styles use the system time zone, which
    /// only follows `TZ` after a reset.
    enum ProcessTimeZone {
        static func set(_ identifier: String) -> String? {
            let previous = ProcessInfo.processInfo.environment["TZ"]
            setenv("TZ", identifier, 1)
            tzset()
            NSTimeZone.resetSystemTimeZone()
            return previous
        }

        static func restore(_ previous: String?) {
            if let previous { setenv("TZ", previous, 1) } else { unsetenv("TZ") }
            tzset()
            NSTimeZone.resetSystemTimeZone()
        }
    }

    /// Renders stories on macOS by hosting them in an offscreen window.
    @MainActor public enum MacRenderer {
        /// The largest canvas, in points, on either axis.
        public static let maximumSize: Double = 4096

        /// Renders `story` once it's stable: two consecutive captures identical.
        ///
        /// Throws ``AdapterError`` if the story can't be read and ``RenderError`` if it never
        /// settles within `timeout` or has an unusable size.
        public static func render(
            _ story: Story, in environment: RenderEnvironment = RenderEnvironment(),
            timeout: Duration = .seconds(2)
        ) async throws -> Snapshot {
            // One render at a time: each sets process-wide state (the time zone) and suspends
            // while waiting to settle, so concurrent renders would see each other's settings.
            let previous = queue
            let current = Task { @MainActor () throws -> Snapshot in
                await previous.value
                return try await renderAlone(story, in: environment, timeout: timeout)
            }
            queue = Task { _ = try? await current.value }
            return try await current.value
        }

        /// The last render in line.
        private static var queue = Task<Void, Never> {}

        private static func renderAlone(
            _ story: Story, in environment: RenderEnvironment, timeout: Duration
        )
            async throws -> Snapshot
        {
            _ = NSApplication.shared

            // `Date.formatted()` and friends read the process's time zone, not SwiftUI's.
            let processTimeZone = ProcessTimeZone.set(environment.timeZoneIdentifier)
            defer { ProcessTimeZone.restore(processTimeZone) }

            let view = AnyView(try await story.makeView().pinned(to: environment))
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 1, height: 1), styleMask: [.borderless],
                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(
                named: environment.appearance == .dark ? .darkAqua : .aqua)
            defer {
                window.contentView = nil
                window.close()
            }

            let size = try canvasSize(of: story, view: view, in: window, environment: environment)
            // The canvas is explicit, so content is centered in it as in Xcode, over the window
            // background (which captures wouldn't otherwise include).
            let host = NSHostingView(
                rootView: AnyView(
                    view.frame(width: size.width, height: size.height)
                        .background(Color(nsColor: .windowBackgroundColor))))
            host.sizingOptions = []
            window.contentView = host
            window.setContentSize(size)
            host.frame = CGRect(origin: .zero, size: size)

            let image = try await stableCapture(
                of: host, size: size, scale: environment.scale, timeout: timeout
            ) {
                RenderError(story: story.id, problem: $0)
            }
            return Snapshot(
                story: story.id, device: .mac, environment: environment, image: image,
                metadata: metadata(for: story, environment: environment))
        }

        private static func canvasSize(
            of story: Story, view: AnyView, in window: NSWindow, environment: RenderEnvironment
        ) throws -> CGSize {
            let device = CGSize(width: environment.deviceWidth, height: environment.deviceHeight)
            var size: CGSize
            switch story.layout {
            case .device:
                size = device
            case .fixed(let width, let height):
                size = CGSize(width: width, height: height)
            case .sizeThatFits:
                let measure = NSHostingView(rootView: view)
                window.contentView = measure
                measure.layoutSubtreeIfNeeded()
                let fitting = measure.fittingSize
                // Views with no ideal size on an axis, such as a List, fill the device instead.
                size = CGSize(
                    width: fitting.width > 0 ? fitting.width : device.width,
                    height: fitting.height > 0 ? fitting.height : device.height)
            }
            guard size.width <= maximumSize, size.height <= maximumSize else {
                throw RenderError(
                    story: story.id, problem: "canvas \(size) exceeds \(maximumSize) points")
            }
            guard size.width > 0, size.height > 0 else {
                throw RenderError(story: story.id, problem: "empty canvas \(size)")
            }
            // Snap to whole pixels, so every capture has the same dimensions.
            let scale = environment.scale
            return CGSize(
                width: (size.width * scale).rounded(.up) / scale,
                height: (size.height * scale).rounded(.up) / scale)
        }

        private static func stableCapture(
            of host: NSView, size: CGSize, scale: Double, timeout: Duration,
            error: (String) -> RenderError
        ) async throws -> CGImage {
            let clock = ContinuousClock()
            let deadline = clock.now + timeout
            var previous: (image: CGImage, pixels: Data)?
            var captures = 0
            while true {
                host.layoutSubtreeIfNeeded()
                prepareForCapture(host)
                host.displayIfNeeded()
                let image = try capture(host, size: size, scale: scale, error: error)
                captures += 1
                guard let pixels = image.dataProvider?.data as Data? else {
                    throw error("capture has no pixels")
                }
                if let previous, previous.pixels == pixels { return image }
                previous = (image, pixels)
                guard clock.now < deadline else {
                    throw error("still changing after \(captures) captures over \(timeout)")
                }
                // Let the run loop process SwiftUI's pending updates.
                try await Task.sleep(for: .milliseconds(16))
            }
        }

        /// Makes chrome that the window server composites capturable by `cacheDisplay`.
        ///
        /// Sidebars draw selection and backgrounds with vibrancy: compositing filters that blend
        /// with what's behind the window, which only the window server applies. Captured as is, a
        /// selected row is a black rectangle. So selected rows are drawn emphasized, as in a
        /// focused sidebar (a solid accent color, no filter), and vibrant backgrounds draw in their
        /// own colors. Vibrant content, such as sidebar text, is composited by ``Vibrancy``.
        static func prepareForCapture(_ view: NSView) {
            if let row = view as? NSTableRowView, row.isSelected, !row.isEmphasized {
                row.isEmphasized = true
            }
            if let layer = view.layer { removeVibrantBackgrounds(from: layer) }
            view.subviews.forEach(prepareForCapture)
        }

        private static func removeVibrantBackgrounds(from layer: CALayer) {
            if let filter = layer.compositingFilter,
                String(describing: filter).hasPrefix("vibrant"),
                !Vibrancy.colorsFromBackdrop(layer)
            {
                layer.compositingFilter = nil
            }
            layer.sublayers?.forEach(removeVibrantBackgrounds)
        }

        /// Captures `view`, compositing any vibrant content over the rest.
        private static func capture(
            _ view: NSView, size: CGSize, scale: Double, error: (String) -> RenderError
        ) throws -> CGImage {
            guard let root = view.layer else {
                return try cacheDisplay(view, size: size, scale: scale, error: error)
            }
            let vibrant = Vibrancy.layers(in: root)
            guard !vibrant.isEmpty else {
                return try cacheDisplay(view, size: size, scale: scale, error: error)
            }
            // Capture the backdrop with the vibrant layers hidden, then restore them so each can
            // be rendered alone for its coverage.
            let opacities = vibrant.map(\.layer.opacity)
            func setOpacities(_ values: [Float]) {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for (vibrant, opacity) in zip(vibrant, values) { vibrant.layer.opacity = opacity }
                CATransaction.commit()
            }
            setOpacities(opacities.map { _ in 0 })
            let backdrop: Bitmap
            do {
                backdrop = try Bitmap(
                    try cacheDisplay(view, size: size, scale: scale, error: error))
            } catch {
                setOpacities(opacities)
                throw error
            }
            setOpacities(opacities)
            guard
                let image = Vibrancy.composite(vibrant, over: backdrop, root: root, scale: scale)
                    .image()
            else {
                throw error("can't composite vibrancy")
            }
            return image
        }

        private static func cacheDisplay(
            _ view: NSView, size: CGSize, scale: Double, error: (String) -> RenderError
        ) throws -> CGImage {
            guard
                let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded()),
                    pixelsHigh: Int((size.height * scale).rounded()), bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                    bitsPerPixel: 0)
            else { throw error("can't allocate a \(size) bitmap at scale \(scale)") }
            // A bitmap whose point size differs from its pixel size draws at that scale,
            // whatever the backing scale of the machine's screens.
            bitmap.size = size
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let srgb = bitmap.converting(to: .sRGB, renderingIntent: .default),
                let image = srgb.cgImage
            else {
                throw error("can't convert the capture to sRGB")
            }
            return image
        }

        private static func metadata(for story: Story, environment: RenderEnvironment)
            -> SnapshotMetadata
        {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return SnapshotMetadata(
                story: story.id.description, device: Device.mac.rawValue, platform: "macOS",
                osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                scale: environment.scale, appearance: environment.appearance.rawValue,
                locale: environment.localeIdentifier, timeZone: environment.timeZoneIdentifier,
                dynamicTypeSize: String(describing: environment.dynamicTypeSize),
                layoutDirection: String(describing: environment.layoutDirection),
                swiftBookVersion: SwiftBookInfo.version)
        }
    }
#endif
