#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook view`: builds and opens the viewer.
    struct ViewCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "view",
            abstract: "Open the SwiftBook viewer on this package.",
            discussion: """
                Builds the viewer from SwiftBook's source, as this package resolved it, and \
                opens it. The viewer keeps running after this command returns; its log is \
                .build/swiftbook/viewer.log.
                """)

        func run() throws {
            do {
                let project = try Project.current()
                FileHandle.standardError.write(Data("Building the viewer…\n".utf8))
                let viewer = try Self.build(in: project.root)
                let log = project.root.appending(path: ".build/swiftbook/viewer.log")
                try FileManager.default.createDirectory(
                    at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: log.path, contents: nil)
                let process = Process()
                // nohup keeps the viewer open when the terminal that started it closes.
                process.executableURL = URL(filePath: "/usr/bin/nohup")
                process.arguments = [viewer.path]
                process.environment = ProcessInfo.processInfo.environment.merging([
                    "SWIFTBOOK_PACKAGE": project.root.path
                ]) { $1 }
                let output = try FileHandle(forWritingTo: log)
                process.standardOutput = output
                process.standardError = output
                process.standardInput = FileHandle.nullDevice
                try process.run()
                print("Opened the SwiftBook viewer on \(project.root.lastPathComponent).")
            } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
        }

        /// Builds the viewer product in `package`, which depends on SwiftBook, and returns it.
        static func build(in package: URL) throws -> URL {
            guard
                let result = Shell.run(
                    ["swift", "build", "--product", "swiftbook-viewer"], in: package)
            else { throw Failure(description: "swift isn't available") }
            guard result.succeeded else {
                throw Failure(
                    description:
                        "couldn't build the viewer:\n\(RendererHost.diagnostics(in: result.output + "\n" + result.error))"
                )
            }
            guard let binPath = Shell.run(["swift", "build", "--show-bin-path"], in: package),
                binPath.succeeded
            else { throw Failure(description: "can't find the viewer's build directory") }
            return URL(filePath: binPath.output).appending(path: "swiftbook-viewer")
        }
    }
#endif
