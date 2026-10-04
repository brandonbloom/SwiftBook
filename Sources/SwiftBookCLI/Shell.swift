#if os(macOS)
    import Foundation

    /// Runs other programs.
    enum Shell {
        struct Result {
            var status: Int32
            var output: String
            var error: String

            var succeeded: Bool { status == 0 }
        }

        /// Runs `arguments` through `env`, so the program is found on `PATH`, and waits for it.
        /// Returns `nil` if it couldn't be started.
        static func run(_ arguments: [String], in directory: URL? = nil) -> Result? {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = directory }
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            // Read before waiting, so a full pipe can't block the program.
            let outputData = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            // `env` exits 127 when the program doesn't exist.
            if process.terminationStatus == 127 { return nil }
            return Result(
                status: process.terminationStatus,
                output: String(decoding: outputData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                error: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
#endif
