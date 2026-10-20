#if os(macOS)
    import AppKit
    import SwiftUI

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
            // Several at once, each in a window of its own: most of a render is waiting for it
            // to settle. The gate keeps the process's time zone, which `Date.formatted()` reads,
            // the same for every render running.
            try await gate.run(in: environment.timeZoneIdentifier) {
                try await renderAlone(story, in: environment, timeout: timeout)
            }
        }

        private static let gate = RenderGate(limit: RenderGate.macLimit())

        private static func renderAlone(
            _ story: Story, in environment: RenderEnvironment, timeout: Duration
        )
            async throws -> Snapshot
        {
            if NSApplication.shared.activationPolicy() == .regular,
                Bundle.main.bundleURL.pathExtension != "app"
            {
                // A test process isn't an app. Otherwise macOS lists it as one while it renders,
                // with a Dock tile that can outlive it. (A regular app can't become prohibited.)
                NSApplication.shared.setActivationPolicy(.accessory)
            }

            let view = AnyView(try await story.makeView().pinned(to: environment))
            let window = makeWindow(appearance: environment.appearance)
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
            window.setFrameOrigin(offscreenOrigin)
            host.frame = CGRect(origin: .zero, size: size)

            func error(_ problem: String) -> RenderError {
                RenderError(story: story.id, problem: problem)
            }
            var method = try CaptureMethod.current()
            if method == .windowServer, !WindowServerCapture.canCapture(size: size) {
                method = .emulated
            }
            let image: CGImage
            switch method {
            case .windowServer:
                let capture = try await WindowServerCapture.prepare(
                    window, size: size, scale: environment.scale)
                image = try await stableCapture(
                    of: host, settling: .windowServer, timeout: timeout,
                    hold: Hold(duration: ProjectConfiguration.hold(for: story.id)), error: error
                ) {
                    try await capture.capture()
                }
            case .emulated:
                image = try await stableCapture(
                    of: host, settling: .emulated, timeout: timeout,
                    hold: Hold(duration: ProjectConfiguration.hold(for: story.id)), error: error
                ) {
                    try capture(host, size: size, scale: environment.scale, error: error)
                }
            }
            var metadata = metadata(for: story, environment: environment)
            metadata.capture = method.rawValue
            return Snapshot(
                story: story.id, device: .mac, environment: environment, image: image,
                metadata: metadata)
        }

        /// Where render windows sit while drawing offscreen: far from every screen, so the real
        /// pointer is never inside one. AppKit's tracking areas check the pointer against a
        /// window's frame even when the window isn't shown, and a window over the pointer draws
        /// hover states.
        static let offscreenOrigin = CGPoint(x: -100_000, y: -100_000)

        /// A borderless window that never sees the pointer, in `appearance`.
        static func makeWindow(appearance: RenderEnvironment.Appearance) -> NSWindow {
            let window = NSWindow(
                contentRect: CGRect(origin: offscreenOrigin, size: CGSize(width: 1, height: 1)),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            // Window-server captures need the window on screen, where the pointer may pass over
            // it; ignoring mouse events keeps hover and cursor tracking off there too.
            window.ignoresMouseEvents = true
            window.acceptsMouseMovedEvents = false
            window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
            return window
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

        /// How long to wait for a render to settle.
        struct Settling {
            /// Before the first capture.
            var initialDelay: Duration
            /// Between captures.
            var interval: Duration
            /// Identical captures in a row that count as settled.
            var matches: Int

            /// Offscreen drawing reflects the view as soon as it's displayed.
            static let emulated = Settling(
                initialDelay: .zero, interval: .milliseconds(16), matches: 2)
            /// The window server shows a window's content a few frames after it's drawn, and two
            /// quick captures can both be stale.
            static let windowServer = Settling(
                initialDelay: .milliseconds(300), interval: .milliseconds(50), matches: 3)
        }

        /// Captures to take before a render counts as still changing, however long they take:
        /// on a loaded machine, one capture can take the whole timeout.
        static let minimumCaptures = 5

        /// Captures `host` until it holds still: as many identical captures in a row as
        /// `settling` needs, and as `hold` does, the first of them at least `hold`'s duration
        /// before the last.
        private static func stableCapture(
            of host: NSView, settling: Settling, timeout: Duration, hold: Hold,
            error: (String) -> RenderError, capture: () async throws -> CGImage
        ) async throws -> CGImage {
            let clock = ContinuousClock()
            let timeout = hold.timeout(otherwise: timeout)
            let deadline = clock.now + settling.initialDelay + timeout
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            try await Task.sleep(for: settling.initialDelay)
            var previous: Data?
            var matches = 1
            // When the first of the current run of identical captures was taken.
            var stableSince = clock.now
            var captures = 0
            while true {
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let taken = clock.now
                let image = try await capture()
                captures += 1
                guard let pixels = image.dataProvider?.data as Data? else {
                    throw error("capture has no pixels")
                }
                if pixels == previous {
                    matches += 1
                } else {
                    matches = 1
                    stableSince = taken
                }
                if matches >= settling.matches,
                    hold.isSatisfied(stable: taken - stableSince, identical: matches)
                {
                    return image
                }
                previous = pixels
                guard clock.now < deadline || captures < minimumCaptures else {
                    throw error("still changing after \(captures) captures over \(timeout)")
                }
                // Let the run loop process SwiftUI's pending updates.
                try await Task.sleep(for: settling.interval)
            }
        }

        /// Captures `view`, compositing any vibrant content over the rest.
        private static func capture(
            _ view: NSView, size: CGSize, scale: Double, error: (String) -> RenderError
        ) throws -> CGImage {
            guard let root = view.layer else {
                return try draw(view, size: size, scale: scale, error: error)
            }
            let plan = Vibrancy.plan(for: root)
            let vibrant = plan.vibrant
            guard !vibrant.isEmpty else {
                return try draw(view, size: size, scale: scale, error: error)
            }
            // Render each vibrant layer alone for its coverage, then capture the backdrop with
            // them hidden.
            let rendered = Vibrancy.render(
                plan, root: root, width: Int((size.width * scale).rounded()),
                height: Int((size.height * scale).rounded()), scale: scale)
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
                    try draw(view, size: size, scale: scale, error: error))
            } catch {
                setOpacities(opacities)
                throw error
            }
            setOpacities(opacities)
            guard
                let image = Vibrancy.composite(rendered, over: backdrop).image()
            else {
                throw error("can't composite vibrancy")
            }
            return image
        }

        /// Draws `view` into a bitmap at `scale`.
        private static func draw(
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
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw error("can't draw into a \(size) bitmap")
            }
            // Not `cacheDisplay`: it marks the view as caching its display, and SwiftUI then swaps
            // Liquid Glass controls for a flat fallback until the window next displays.
            view.displayIgnoringOpacity(view.bounds, in: context)
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
                swiftBookVersion: SwiftBookInfo.version,
                tint: ProjectConfiguration.tintDescription(in: environment.appearance))
        }
    }
#endif
