#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook simulator-idle`: shuts an extra pooled simulator down once it has been idle.
    ///
    /// A run that releases an extra simulator starts this in the background, so the next run
    /// within a few minutes finds the simulator booted. Not for people to run.
    struct SimulatorIdleCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "simulator-idle",
            abstract: "Shut a pooled simulator down once it has been idle.",
            shouldDisplay: false)

        @Option var device: Device
        @Option var number: Int

        func run() throws {
            try SimulatorPool.shutDownWhenIdle(device, number: number)
        }

        /// Starts `swiftbook simulator-idle` for `device`'s simulator `number`, detached, so it
        /// outlives this process.
        static func start(_ device: Device, number: Int) {
            let process = Process()
            process.executableURL = URL(filePath: CommandLine.arguments[0]).absoluteURL
            process.arguments = [
                "simulator-idle", "--device", "\(device)", "--number", String(number),
            ]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            // Best effort: if it can't start, the simulator stays booted until the next run's
            // release starts another.
            try? process.run()
        }
    }
#endif
