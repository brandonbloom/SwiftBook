#if os(macOS)
    import ArgumentParser
    import Foundation

    /// The `swiftbook` command.
    public struct SwiftBookCommand: ParsableCommand {
        public static let configuration = CommandConfiguration(
            commandName: "swiftbook",
            abstract: "Snapshot tests and a story viewer for SwiftUI previews.",
            discussion: """
                Exit status: 0 for success, \(Exit.changed.rawValue) when snapshots changed or \
                failed, \(Exit.broken.rawValue) when something else went wrong, and 64 for usage \
                errors.
                """,
            subcommands: [
                ViewCommand.self, TestCommand.self, DiffCommand.self, ReviewCommand.self,
                ListCommand.self,
                RenderCommand.self,
                PruneCommand.self,
                InitCommand.self,
                DoctorCommand.self,
            ])

        public init() {}
    }

    /// Exit statuses, so scripts can tell changed snapshots from failures of the tool or setup.
    public enum Exit: Int32, Sendable {
        case success = 0
        /// Snapshots changed or didn't match.
        case changed = 1
        /// Something other than snapshots went wrong: setup, toolchain, or SwiftBook itself.
        case broken = 2

        var code: ExitCode { ExitCode(rawValue) }
    }

    /// A failure that should end the command with a message and ``Exit/broken``.
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    extension ParsableCommand {
        /// Writes `message` to standard error.
        func warn(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    }
#endif
