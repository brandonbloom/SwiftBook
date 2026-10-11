#if os(macOS)
    import Foundation

    /// A simulated device, driven through `simctl`.
    public struct Simulator: Sendable {
        public let udid: String
        public let name: String

        /// The device type SwiftBook pins for each device class, so renders don't depend on
        /// which simulators someone happens to have.
        static func deviceType(for device: Device) throws -> (
            id: String, name: String, platform: String
        ) {
            switch device {
            case .iphone:
                ("com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro", "iPhone 17 Pro", "iOS")
            case .ipad:
                (
                    "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-11-inch-M5-12GB",
                    "iPad Pro 11-inch", "iOS"
                )
            case .tv:
                (
                    "com.apple.CoreSimulator.SimDeviceType.Apple-TV-4K-3rd-generation-4K",
                    "Apple TV 4K", "tvOS"
                )
            case .mac, .catalyst:
                throw RendererError(description: "\(device) renders without a simulator")
            }
        }

        /// SwiftBook's own simulator for `device` on the newest installed runtime of its platform
        /// (27 or later), created if it doesn't exist yet and booted. `number` picks one from
        /// ``SimulatorPool``: the first is named for its device, and the others add `#2`, `#3`,
        /// and so on.
        public static func dedicated(for device: Device, number: Int = 1, boot: Bool = true)
            throws -> Simulator
        {
            let type = try deviceType(for: device)
            let runtimes =
                try simctlJSON(["list", "runtimes", "--json"])["runtimes"] as? [[String: Any]] ?? []
            let runtime = runtimes.filter {
                ($0["platform"] as? String) == type.platform && ($0["isAvailable"] as? Bool) == true
                    && (($0["version"] as? String).flatMap { Int($0.prefix { $0 != "." }) } ?? 0)
                        >= 27
            }.max {
                ($0["version"] as? String ?? "").compare(
                    $1["version"] as? String ?? "", options: .numeric) == .orderedAscending
            }
            guard let runtime, let runtimeID = runtime["identifier"] as? String,
                let version = runtime["version"] as? String
            else {
                throw RendererError(
                    description:
                        "No \(type.platform) 27 simulator runtime is installed. Install one in Xcode › Settings › Components."
                )
            }
            let name =
                "SwiftBook \(type.name)\(number > 1 ? " #\(number)" : "") (\(type.platform) \(version))"
            let devices =
                try simctlJSON(["list", "devices", "--json"])["devices"]
                as? [String: [[String: Any]]] ?? [:]
            let udid: String
            if let existing = devices[runtimeID]?.first(where: {
                ($0["name"] as? String) == name && ($0["isAvailable"] as? Bool) == true
            }), let id = existing["udid"] as? String {
                udid = id
            } else {
                udid = try simctl(["create", name, type.id, runtimeID]).output
            }
            let simulator = Simulator(udid: udid, name: name)
            if boot { try simulator.boot() }
            return simulator
        }

        /// Boots the simulator if it isn't already, and waits until it's ready.
        public func boot() throws {
            // `bootstatus -b` boots if needed and waits for the device to finish booting.
            _ = try Self.simctl(["bootstatus", udid, "-b"])
        }

        /// Shuts the simulator down, if it's booted.
        public func shutdown() {
            _ = Shell.run(["xcrun", "simctl", "shutdown", udid])
        }

        /// Installs the app at `app`, replacing any earlier copy.
        public func install(_ app: URL) throws {
            _ = try Self.simctl(["install", udid, app.path])
        }

        /// Launches the installed app with `bundleID`, ending any running copy first, and returns
        /// its process identifier. Its standard error goes to `errorLog`. `environment` is passed
        /// to the app.
        public func launch(bundleID: String, environment: [String: String], errorLog: URL) throws
            -> pid_t
        {
            // simctl passes variables prefixed with SIMCTL_CHILD_ to the app, unprefixed.
            let result = try Self.simctl(
                [
                    "launch", "--terminate-running-process", "--stderr=\(errorLog.path)", udid,
                    bundleID,
                ],
                environment: Dictionary(
                    uniqueKeysWithValues: environment.map { ("SIMCTL_CHILD_\($0)", $1) }))
            // "<bundle ID>: <pid>"
            guard let pid = result.output.split(separator: " ").last.flatMap({ pid_t($0) }) else {
                throw RendererError(
                    description: "simctl launch printed no process ID: \(result.output)")
            }
            return pid
        }

        private static func simctl(_ arguments: [String], environment: [String: String] = [:])
            throws
            -> Shell.Result
        {
            guard let result = Shell.run(["xcrun", "simctl"] + arguments, environment: environment)
            else { throw RendererError(description: "simctl isn't available; install Xcode") }
            guard result.succeeded else {
                throw RendererError(
                    description:
                        "simctl \(arguments.joined(separator: " ")) failed: \(result.error)")
            }
            return result
        }

        private static func simctlJSON(_ arguments: [String]) throws -> [String: Any] {
            let result = try simctl(arguments)
            guard
                let object = try? JSONSerialization.jsonObject(with: result.data) as? [String: Any]
            else {
                throw RendererError(description: "simctl \(arguments.first ?? "") printed no JSON")
            }
            return object
        }
    }
#endif
