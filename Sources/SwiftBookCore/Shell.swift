#if os(macOS)
    import Foundation

    /// Runs other programs.
    package enum Shell {
        package struct Result: Sendable {
            package var status: Int32
            /// Everything the program wrote to standard output.
            package var data: Data
            /// Standard error, trimmed.
            package var error: String

            package var succeeded: Bool { status == 0 }
            /// Standard output as text, trimmed.
            package var output: String {
                String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        /// Runs `arguments` through `env`, so the program is found on `PATH`, and waits for it.
        /// `environment` adds to this process's environment. Returns `nil` if the program
        /// couldn't be started.
        package static func run(
            _ arguments: [String], in directory: URL? = nil, environment: [String: String] = [:]
        ) -> Result? {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = directory }
            if !environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) {
                    $1
                }
            }
            let output = Pipe()
            let error = Pipe()
            process.standardOutput = output
            process.standardError = error
            process.standardInput = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            // Drain both pipes at once, so a program filling one can't block on it while this
            // waits on the other. The second reader is a GCD thread, not a Swift task: waiting
            // on a task here could deadlock when every cooperative thread is busy waiting too.
            nonisolated(unsafe) var errorData = Data()
            let errorRead = DispatchGroup()
            errorRead.enter()
            DispatchQueue.global().async {
                errorData = error.fileHandleForReading.readDataToEndOfFile()
                errorRead.leave()
            }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            errorRead.wait()
            let status = exitStatus(of: process)
            // `env` exits 127 when the program doesn't exist.
            if status == 127 { return nil }
            return Result(
                status: status, data: data,
                error: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }

        /// Waits for `process`, whose output has closed, to exit, and returns its status.
        ///
        /// Not `waitUntilExit`: off the main thread, Foundation can fail to notice an exit, and
        /// that waits forever. This polls for a while, then reaps the process itself.
        private static func exitStatus(of process: Process) -> Int32 {
            let deadline = ContinuousClock.now + .seconds(5)
            while process.isRunning, ContinuousClock.now < deadline { usleep(1_000) }
            guard process.isRunning else { return process.terminationStatus }
            var status: Int32 = 0
            guard waitpid(process.processIdentifier, &status, 0) > 0 else { return -1 }
            // The status as WEXITSTATUS would decode it, or 128 plus the signal that ended it.
            return status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        }
    }
#endif
