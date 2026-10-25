#if os(macOS)
    import ApplicationServices
    import Foundation

    /// Keeps a process that isn't an app, such as `swift test`'s test helper, out of the Dock.
    ///
    /// Showing a window, resolving a color through AppKit, or loading a PDF makes such a process a
    /// regular app, which macOS lists under the app that launched it, such as Terminal or an agent's
    /// host app, with a Dock tile that can outlive it. Switching to an accessory app afterwards is
    /// too late: the tile has already appeared. Before any of that, this makes the process a UI
    /// element instead, with no Dock tile or menu bar, though it can still show and capture
    /// windows. Apps are left as they are.
    package enum OutOfDock {
        /// Once per process, before anything that reaches AppKit. Cheap after the first time.
        package static func ensure() { _ = ensured }

        private static let ensured: Void = {
            guard Bundle.main.bundleIdentifier == nil, Bundle.main.bundleURL.pathExtension.isEmpty
            else { return }
            var process = ProcessSerialNumber(
                highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
            let status = TransformProcessType(
                &process, ProcessApplicationTransformState(kProcessTransformToUIElementApplication))
            if status != noErr {
                FileHandle.standardError.write(
                    Data(
                        "warning: SwiftBook couldn't keep this process out of the Dock (OSStatus \(status)); it may show a Dock tile while it renders\n"
                            .utf8))
            }
        }()
    }
#endif
