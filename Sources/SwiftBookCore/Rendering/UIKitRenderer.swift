#if os(iOS) || os(tvOS)
    import SwiftUI
    import UIKit

    /// Renders stories on iOS and tvOS by hosting them in a window of the renderer app.
    ///
    /// Needs a real app process with a window scene: in a test bundle without a host app,
    /// `drawHierarchy` draws nothing.
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

            let view = AnyView(try await story.makeView().pinned(to: environment))
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = environment.appearance == .dark ? .dark : .light
            window.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(
                environment.dynamicTypeSize)
            window.traitOverrides.layoutDirection =
                environment.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            let host = UIHostingController(rootView: view)
            let size: CGSize
            switch story.layout {
            case .device:
                // The whole screen, with the device's safe areas, as in Xcode's canvas.
                size = scene.screen.bounds.size
            case .fixed(let width, let height):
                host.safeAreaRegions = []
                size = CGSize(width: width, height: height)
            case .sizeThatFits:
                // Without this, the safe area inflates the measured size.
                host.safeAreaRegions = []
                let screen = scene.screen.bounds.size
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
                of: window, scale: scale, timeout: timeout, error: error)
            let os = ProcessInfo.processInfo.operatingSystemVersion
            let device = Self.device
            return Snapshot(
                story: story.id, device: device, environment: environment, image: image,
                metadata: SnapshotMetadata(
                    story: story.id.description, device: device.rawValue,
                    platform: device == .tv ? "tvOS" : "iOS",
                    osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                    scale: scale, appearance: environment.appearance.rawValue,
                    locale: environment.localeIdentifier, timeZone: environment.timeZoneIdentifier,
                    dynamicTypeSize: String(describing: environment.dynamicTypeSize),
                    layoutDirection: String(describing: environment.layoutDirection),
                    swiftBookVersion: SwiftBookInfo.version))
        }

        private static func stableCapture(
            of window: UIWindow, scale: Double, timeout: Duration, error: (String) -> RenderError
        ) async throws -> CGImage {
            let deadline = ContinuousClock.now + timeout
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            var previous: Data?
            var captures = 0
            while true {
                window.layoutIfNeeded()
                let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image {
                    _ in
                    _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                captures += 1
                // Normalize to 8-bit sRGB, like macOS captures.
                guard let cgImage = image.cgImage, let normalized = try Bitmap(cgImage).image(),
                    let pixels = normalized.dataProvider?.data as Data?
                else { throw error("capture has no pixels") }
                if pixels == previous { return normalized }
                previous = pixels
                guard ContinuousClock.now < deadline else {
                    throw error("still changing after \(captures) captures over \(timeout)")
                }
                try await Task.sleep(for: .milliseconds(16))
            }
        }
    }
#endif
