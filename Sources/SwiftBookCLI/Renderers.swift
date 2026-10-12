#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// The help for a `--device` option.
    let deviceHelp = ArgumentHelp(
        "The device to render on: mac, iphone, ipad, or tv. Platform names work too: macos, ios (iphone), and tvos (tv).",
        valueName: "device")

    extension Device: ExpressibleByArgument {
        public init?(argument: String) {
            switch argument.lowercased() {
            case "mac", "macos": self = .mac
            case "iphone", "ios": self = .iphone
            case "ipad": self = .ipad
            case "tv", "tvos": self = .tv
            default: return nil
            }
        }

        public static var allValueStrings: [String] { ["mac", "iphone", "ipad", "tv"] }
    }

    /// Starting renderers for the CLI.
    enum Renderers {
        /// Builds the renderer for `project` and starts it on `device`: as a process for the
        /// Mac, or as an app in SwiftBook's own simulator for the others. It restarts when it
        /// crashes or hangs.
        static func start(for project: Project, on device: Device = .mac) throws
            -> RestartingRenderer
        {
            let host = RendererHost(package: project.root)
            switch device {
            case .mac:
                progress("Building the renderer…")
                let executable = try host.build()
                return try RestartingRenderer { try RendererProcess(executable: executable) }
            case .iphone, .ipad, .tv:
                let app = try buildApp(for: project, on: device)
                progress("Starting the simulator…")
                // A simulator of this run's own: runs sharing one suspend each other's renderers.
                // Extra simulators stay booted for a few minutes after the run, for the next one.
                return try start(
                    app,
                    in: SimulatorPool.lease(
                        for: device, waiting: progress, keepWarm: SimulatorIdleCommand.start))
            case .catalyst:
                throw Failure(description: "Mac Catalyst rendering isn't supported yet.")
            }
        }

        /// Builds the renderer app for `device`, a simulated one.
        static func buildApp(for project: Project, on device: Device) throws -> RendererHost.App {
            progress("Building the \(device == .tv ? "tvOS" : "iOS") renderer…")
            return try RendererHost(package: project.root).buildApp(
                for: device == .tv ? .tvOS : .iOS)
        }

        /// Starts `app` in `lease`'s simulator, giving the lease back when the renderer shuts
        /// down.
        static func start(_ app: RendererHost.App, in lease: SimulatorLease) throws
            -> RestartingRenderer
        {
            do {
                return try RestartingRenderer {
                    try RendererProcess(app: app.url, bundleID: app.bundleID, in: lease.simulator)
                } onShutdown: {
                    lease.release()
                }
            } catch {
                lease.release()
                throw error
            }
        }

        static func progress(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    }
#endif
