#if os(macOS)
    import AppKit
    import ScreenCaptureKit

    /// How a macOS render was captured.
    package enum CaptureMethod: String, Hashable, Sendable, CaseIterable {
        /// Captured from the window server with ScreenCaptureKit: exactly what's on screen,
        /// including vibrancy and Liquid Glass. Needs Screen Recording permission.
        case windowServer
        /// Drawn offscreen by the view itself, with vibrancy composited by ``Vibrancy``: close to
        /// the window server, but not exact.
        case emulated

        /// The variable that forces a capture method.
        package static let environmentVariable = "SWIFTBOOK_CAPTURE"

        /// The method set by `SWIFTBOOK_CAPTURE`, or else ``windowServer`` when this process may
        /// record the screen and the screen is unlocked, and ``emulated`` otherwise.
        package static func current(
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
        package static var screenIsLocked: Bool {
            let session = CGSessionCopyCurrentDictionary() as? [String: Any]
            return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        }
    }

    struct RenderErrorDescription: Error, CustomStringConvertible {
        let description: String
    }

    /// Captures a window through the window server.
    ///
    /// The window is ordered in below the desktop, so nothing flashes on screen and focus isn't
    /// taken; ScreenCaptureKit captures it identically to a window in front.
    @MainActor struct WindowServerCapture {
        private let filter: SCContentFilter
        private let configuration: SCStreamConfiguration

        /// Whether `size` fits on the main screen, where the window must be to be captured.
        static func canCapture(size: CGSize) -> Bool {
            guard let screen = NSScreen.main else { return false }
            return size.width <= screen.frame.width && size.height <= screen.frame.height
        }

        /// Orders `window` in below the desktop, on screen, and finds it for ScreenCaptureKit.
        static func prepare(_ window: NSWindow, size: CGSize, scale: Double) async throws
            -> WindowServerCapture
        {
            if let screen = NSScreen.main { window.setFrameOrigin(screen.frame.origin) }
            // Below the desktop, the wallpaper covers the window, yet the window server still
            // draws it. Out of Mission Control and window cycling, it's ordered in and out
            // without an animation. Captures are identical either way.
            window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
            window.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) - 1)
            window.orderBack(nil)
            let windowID = CGWindowID(window.windowNumber)
            for _ in 0..<50 {
                let content = try await answer {
                    try await SCShareableContent.excludingDesktopWindows(
                        false, onScreenWindowsOnly: false)
                }
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
                image = try await Self.answer {
                    try await SCScreenshotManager.captureImage(
                        contentFilter: filter, configuration: configuration)
                }
            } catch let error as RenderErrorDescription {
                throw error
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

    extension WindowServerCapture {
        /// How long ScreenCaptureKit gets to answer a call.
        static let deadline = Duration.seconds(10)

        /// `call`'s result, unless ScreenCaptureKit takes longer than ``deadline``. It can wait
        /// indefinitely, for example while macOS asks whether to allow screen recording.
        @MainActor static func answer<T>(_ call: @escaping @MainActor () async throws -> T)
            async throws -> T
        {
            try await withCheckedThrowingContinuation { continuation in
                // Whichever finishes first, the call or the deadline, resumes.
                let finished = Finished()
                let work = Task { @MainActor in
                    // Unsafe: ScreenCaptureKit's results aren't Sendable, but this hands one
                    // from the main actor to a caller on the main actor.
                    nonisolated(unsafe) let result = await Result { try await call() }
                    if finished.claim() { continuation.resume(with: result) }
                }
                Task { @MainActor in
                    try? await Task.sleep(for: deadline)
                    guard finished.claim() else { return }
                    work.cancel()
                    continuation.resume(
                        throwing: RenderErrorDescription(
                            description: """
                                the window server didn't answer within \(deadline). macOS may be \
                                waiting for someone to allow screen recording; check for its \
                                prompt, or set \(CaptureMethod.environmentVariable)=emulated.
                                """))
                }
            }
        }

        /// Whether a race has been decided.
        @MainActor private final class Finished {
            private var done = false

            /// True the first time only.
            func claim() -> Bool {
                defer { done = true }
                return !done
            }
        }
    }
#endif
