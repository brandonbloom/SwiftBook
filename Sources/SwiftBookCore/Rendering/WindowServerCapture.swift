#if os(macOS)
    import AppKit
    import ScreenCaptureKit

    /// How a macOS render was captured.
    public enum CaptureMethod: String, Hashable, Sendable, CaseIterable {
        /// Captured from the window server with ScreenCaptureKit: exactly what's on screen,
        /// including vibrancy and Liquid Glass. Needs Screen Recording permission.
        case windowServer
        /// Drawn offscreen by the view itself, with vibrancy composited by ``Vibrancy``: close to
        /// the window server, but not exact.
        case emulated

        /// The variable that forces a capture method.
        public static let environmentVariable = "SWIFTBOOK_CAPTURE"

        /// The method set by `SWIFTBOOK_CAPTURE`, or else ``windowServer`` when this process may
        /// record the screen and the screen is unlocked, and ``emulated`` otherwise.
        public static func current(
            _ environment: [String: String] = ProcessInfo.processInfo.environment
        )
            throws -> CaptureMethod
        {
            if let value = environment[environmentVariable], !value.isEmpty {
                guard let method = CaptureMethod(rawValue: value) else {
                    let methods = allCases.map(\.rawValue).joined(separator: ", ")
                    throw RenderErrorDescription(
                        description: "\(environmentVariable)=\(value) isn't one of \(methods)")
                }
                return method
            }
            return CGPreflightScreenCaptureAccess() && !screenIsLocked ? .windowServer : .emulated
        }

        /// Whether the console session is locked, when the window server captures nothing.
        public static var screenIsLocked: Bool {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
    }

    struct RenderErrorDescription: Error, CustomStringConvertible {
        let description: String
    }

    /// Captures a window through the window server.
    ///
    /// The window is ordered behind all others, so nothing flashes on screen and focus isn't
    /// taken; ScreenCaptureKit captures it identically to a window in front.
    @MainActor struct WindowServerCapture {
        private let filter: SCContentFilter
        private let configuration: SCStreamConfiguration

        /// Whether `size` fits on the main screen, where the window must be to be captured.
        static func canCapture(size: CGSize) -> Bool {
            guard let screen = NSScreen.main else { return false }
            return size.width <= screen.frame.width && size.height <= screen.frame.height
        }

        /// Orders `window` behind all others, on screen, and finds it for ScreenCaptureKit.
        static func prepare(_ window: NSWindow, size: CGSize, scale: Double) async throws
            -> WindowServerCapture
        {
            if let screen = NSScreen.main { window.setFrameOrigin(screen.frame.origin) }
            window.orderBack(nil)
            let windowID = CGWindowID(window.windowNumber)
            for _ in 0..<50 {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false)
                if let scWindow = content.windows.first(where: { $0.windowID == windowID }) {
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int((size.width * scale).rounded())
                    configuration.height = Int((size.height * scale).rounded())
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true
                    configuration.colorSpaceName = CGColorSpace.sRGB
                    return WindowServerCapture(
                        filter: SCContentFilter(desktopIndependentWindow: scWindow),
                        configuration: configuration)
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            throw RenderErrorDescription(
                description: "the window server never listed the render window")
        }

        func capture() async throws -> CGImage {
            let image: CGImage
            do {
                image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: configuration)
            } catch {
                let reason =
                    CaptureMethod.screenIsLocked
                    ? "the screen is locked" : error.localizedDescription
                throw RenderErrorDescription(
                    description: """
                        the window server couldn't capture the window (\(reason)). Unlock the \
                        screen, or set \(CaptureMethod.environmentVariable)=emulated.
                        """)
            }
            // Normalize to 8-bit sRGB, like emulated captures.
            guard let normalized = try Bitmap(image).image() else {
                throw RenderErrorDescription(description: "can't read the window server's capture")
            }
            return normalized
        }
    }
#endif
