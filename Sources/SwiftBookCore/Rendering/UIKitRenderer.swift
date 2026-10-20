#if os(iOS) || os(tvOS)
    import SwiftUI
    import UIKit

    /// Renders stories on iOS and tvOS by hosting them in a window of the renderer app.
    ///
    /// Needs a real app process with a window scene: in a test bundle without a host app,
    /// `drawHierarchy` draws nothing. On iOS, the app's scene rotates to each story's
    /// orientation, so the app must allow every orientation.
    @MainActor public enum UIKitRenderer {
        /// The device this process renders as.
        public static var device: Device {
            #if os(tvOS)
                .tv
            #else
                UIDevice.current.userInterfaceIdiom == .pad ? .ipad : .iphone
            #endif
        }

        /// Renders `story` once two consecutive captures are identical.
        ///
        /// Throws ``AdapterError`` if the story can't be read and ``RenderError`` if it never
        /// settles within `timeout` or has an unusable size.
        public static func render(
            _ story: Story, in environment: RenderEnvironment, timeout: Duration = .seconds(2)
        ) async throws -> Snapshot {
            // One render at a time: each sets process-wide state (the time zone).
            let previous = queue
            let current = Task { @MainActor () throws -> Snapshot in
                await previous.value
                return try await renderAlone(story, in: environment, timeout: timeout)
            }
            queue = Task { _ = try? await current.value }
            return try await current.value
        }

        private static var queue = Task<Void, Never> {}

        private static func renderAlone(
            _ story: Story, in environment: RenderEnvironment, timeout: Duration
        ) async throws -> Snapshot {
            func error(_ problem: String) -> RenderError {
                RenderError(story: story.id, problem: problem)
            }
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first
            else { throw error("the renderer app has no window scene") }

            let processTimeZone = ProcessTimeZone.set(environment.timeZoneIdentifier)
            defer { ProcessTimeZone.restore(processTimeZone) }
            UIView.setAnimationsEnabled(false)

            #if os(iOS)
                // The story's orientation, or portrait. The whole scene rotates, as the device
                // would.
                try await rotate(scene, to: story.orientation ?? .portrait, error: error)
            #endif

            let view = AnyView(try await story.makeView().pinned(to: environment))
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = environment.appearance == .dark ? .dark : .light
            window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(
                environment.dynamicTypeSize)
            window.traitOverrides.layoutDirection =
                environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
            // Stop the window's clock before any content arrives, so every animation, such as an
            // indeterminate ProgressView's spin, stays on its first frame. Core Animation runs
            // animations out of process, so disabling UIKit's animations isn't enough.
            window.layer.speed = 0
            window.layer.timeOffset = 0
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            let host = UIHostingController(rootView: view)
            let size: CGSize
            switch story.layout {
            case .device:
                // The whole screen, with the device's safe areas, as in Xcode's canvas.
                size = scene.effectiveGeometry.coordinateSpace.bounds.size
            case .fixed(let width, let height):
                host.safeAreaRegions = []
                size = CGSize(width: width, height: height)
            case .sizeThatFits:
                // Without this, the safe area inflates the measured size.
                host.safeAreaRegions = []
                let screen = scene.effectiveGeometry.coordinateSpace.bounds.size
                let fitting = host.sizeThatFits(in: screen)
                size = CGSize(
                    width: fitting.width > 0 && fitting.width.isFinite
                        ? fitting.width : screen.width,
                    height: fitting.height > 0 && fitting.height.isFinite
                        ? fitting.height : screen.height)
            }
            guard size.width > 0, size.height > 0, size.width <= 4096, size.height <= 4096 else {
                throw error("unusable canvas \(size)")
            }
            let scale = environment.scale
            let canvas = CGSize(
                width: (size.width * scale).rounded(.up) / scale,
                height: (size.height * scale).rounded(.up) / scale)
            window.frame = CGRect(origin: .zero, size: canvas)
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            #if os(tvOS)
                // tvOS has no system background color; its windows are black or white.
                host.view.backgroundColor = environment.appearance == .dark ? .black : .white
            #else
                host.view.backgroundColor = .systemBackground
            #endif

            let image = try await stableCapture(
                of: window, scale: scale, timeout: timeout,
                hold: ProjectConfiguration.hold(for: story.id), error: error)
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let device = Self.device
            var snapshot = Snapshot(
                story: story.id, device: device, environment: environment, image: image,
                metadata: SnapshotMetadata(
                    story: story.id.description, device: device.rawValue,
                    platform: device == .tv ? "tvOS" : "iOS",
                    osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                    scale: scale, appearance: environment.appearance.rawValue,
                    locale: environment.localeIdentifier, timeZone: environment.timeZoneIdentifier,
                    dynamicTypeSize: String(describing: environment.dynamicTypeSize),
                    layoutDirection: String(describing: environment.layoutDirection),
                    swiftBookVersion: SwiftBookInfo.version,
                    tint: ProjectConfiguration.tintDescription(in: environment.appearance)))
            snapshot.glassRegions = glassRegions(
                in: window, scale: scale, width: image.width, height: image.height)
            return snapshot
        }

        /// Where `window` has Liquid Glass, in the capture's pixels: every visible backdrop layer
        /// with filters, which is how glass samples what's behind it, grown by 4 points to cover
        /// its edges. The render server draws these in a few states from run to run.
        static func glassRegions(in window: UIWindow, scale: Double, width: Int, height: Int)
            -> [ImageDiff.PixelRect]
        {
            var regions: [ImageDiff.PixelRect] = []
            func visit(_ layer: CALayer) {
                guard !layer.isHidden, layer.opacity > 0 else { return }
                if NSStringFromClass(type(of: layer)) == "CABackdropLayer",
                    !(layer.filters ?? []).isEmpty, !layer.bounds.isEmpty
                {
                    let frame = layer.convert(layer.bounds, to: window.layer).insetBy(
                        dx: -4, dy: -4)
                    let x = max(Int((frame.minX * scale).rounded(.down)), 0)
                    let y = max(Int((frame.minY * scale).rounded(.down)), 0)
                    let maxX = min(Int((frame.maxX * scale).rounded(.up)), width)
                    let maxY = min(Int((frame.maxY * scale).rounded(.up)), height)
                    if maxX > x, maxY > y {
                        regions.append(.init(x: x, y: y, width: maxX - x, height: maxY - y))
                    }
                }
                layer.sublayers?.forEach(visit)
            }
            visit(window.layer)
            return regions
        }

        #if os(iOS)
            /// Rotates `scene` to `orientation` and waits until it has.
            private static func rotate(
                _ scene: UIWindowScene, to orientation: StoryOrientation,
                error: (String) -> RenderError
            ) async throws {
                let (mask, target): (UIInterfaceOrientationMask, UIInterfaceOrientation) =
                    switch orientation {
                    case .portrait: (.portrait, .portrait)
                    case .portraitUpsideDown: (.portraitUpsideDown, .portraitUpsideDown)
                    case .landscapeLeft: (.landscapeLeft, .landscapeLeft)
                    case .landscapeRight: (.landscapeRight, .landscapeRight)
                    }
                guard scene.effectiveGeometry.interfaceOrientation != target else { return }
                RendererOrientation.allowed = mask
                for window in scene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
                let deadline = ContinuousClock.now + .seconds(3)
                while scene.effectiveGeometry.interfaceOrientation != target {
                    guard ContinuousClock.now < deadline else {
                        throw error("the device didn't rotate to \(orientation)")
                    }
                    try await Task.sleep(for: .milliseconds(20))
                }
            }
        #endif

        /// How long a capture that's all one color must hold before it counts as settled: a
        /// blank capture may come before a presentation, such as a sheet, has drawn.
        static let uniformSettling = Duration.seconds(1)

        /// Captures to take before a render counts as still changing, however long they take:
        /// on a loaded machine, one capture can take the whole timeout.
        static let minimumCaptures = 5

        /// Whether every pixel of 32-bit `pixels` is the same: whether the buffer equals itself
        /// shifted by one pixel. `memcmp` keeps this fast in the debug builds renderers use,
        /// where a Swift loop over millions of pixels takes seconds.
        static func isUniform(_ pixels: Data) -> Bool {
            guard pixels.count > 4 else { return true }
            return pixels.withUnsafeBytes { buffer in
                memcmp(buffer.baseAddress!, buffer.baseAddress! + 4, buffer.count - 4) == 0
            }
        }

        /// Captures `window` until it holds still: two captures in a row identical, held for long
        /// enough for what the capture shows, and for at least `hold`.
        private static func stableCapture(
            of window: UIWindow, scale: Double, timeout: Duration, hold: Duration,
            error: (String) -> RenderError
        ) async throws -> CGImage {
            let start = ContinuousClock.now
            let deadline = start + timeout + max(uniformSettling, hold)
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            var previous: Data?
            var previousTime = start
            // When the current run of identical captures began.
            var stableSince: ContinuousClock.Instant?
            var captures = 0
            while true {
                window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image {
                    _ in
                    _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let now = ContinuousClock.now
                captures += 1
                // Normalize to 8-bit sRGB, like macOS captures.
                guard let cgImage = image.cgImage, let normalized = try Bitmap(cgImage).image(),
                    let pixels = normalized.dataProvider?.data as Data?
                else { throw error("capture has no pixels") }
                if pixels == previous {
                    let since = stableSince ?? previousTime
                    stableSince = since
                    let needed = max(Self.isUniform(pixels) ? uniformSettling : .zero, hold)
                    if now - since >= needed { return normalized }
                } else {
                    stableSince = nil
                }
                previous = pixels
                previousTime = now
                guard now < deadline || captures < minimumCaptures else {
                    throw error("still changing after \(captures) captures over \(timeout)")
                }
                try await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    #if os(iOS)
        /// The orientations the renderer app allows right now: only the one being rendered, so a
        /// requested rotation sticks.
        @MainActor public enum RendererOrientation {
            public static var allowed: UIInterfaceOrientationMask = .portrait
        }
    #endif
#endif
