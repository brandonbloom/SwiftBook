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
            // waits on the other.
            let errorReader = Task.detached { error.fileHandleForReading.readDataToEndOfFile() }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorReader.waitForResult()
            process.waitUntilExit()
            // `env` exits 127 when the program doesn't exist.
            if process.terminationStatus == 127 { return nil }
            return Result(
                status: process.terminationStatus, data: data,
                error: String(decoding: errorData, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    extension Task where Failure == Never {
        /// Blocks until the task finishes. Only for tasks that never wait on the caller.
        fileprivate func waitForResult() -> Success {
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var result: Success?
            Task<Void, Never>.detached {
                result = await self.value
                semaphore.signal()
            }
            semaphore.wait()
            return result!
        }
    }
#endif
