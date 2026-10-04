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
        /// Mac, or as an app in SwiftBook's own simulator for the others.
        static func start(for project: Project, on device: Device = .mac) throws
            -> RendererProcess
        {
            let host = RendererHost(package: project.root)
            switch device {
            case .mac:
                progress("Building the renderer…")
                return try RendererProcess(executable: host.build())
            case .iphone, .ipad, .tv:
                progress("Building the \(device == .tv ? "tvOS" : "iOS") renderer…")
                let app = try host.buildApp(for: device == .tv ? .tvOS : .iOS)
                progress("Starting the simulator…")
                let simulator = try Simulator.dedicated(for: device)
                return try RendererProcess(app: app.url, bundleID: app.bundleID, in: simulator)
            case .catalyst:
                throw Failure(description: "Mac Catalyst rendering isn't supported yet.")
            }
        }

        private static func progress(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    }
#endif
