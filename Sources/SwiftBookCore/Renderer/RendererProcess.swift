#if os(macOS)
    import Foundation

    /// A renderer failed: it couldn't start, crashed, hung, or reported an error.
    public struct RendererError: Error, CustomStringConvertible, Sendable {
        public let description: String
    }

    /// A running renderer process, spoken to over ``RendererProtocol``.
    ///
    /// Requests are answered one at a time, in order. A request that outlives its timeout stops
    /// the renderer; a crashed or stopped renderer fails every later request.
    public final class RendererProcess: @unchecked Sendable {
        // Unchecked: `lock` guards the mutable state.

        /// What the renderer said when it started.
        public let hello: RendererHello
        private let process: Process
        private let input: FileHandle
        private let lines = LineQueue()
        private let errorTail = Tail()
        private let lock = NSLock()
        private var nextID = 1

        /// Starts `executable` and waits for its hello. `environment` adds to this process's.
        public init(
            executable: URL, environment: [String: String] = [:], timeout: Duration = .seconds(60)
        ) throws {
            process = Process()
            process.executableURL = executable
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            input = inputPipe.fileHandleForWriting
            // Writing to a renderer that crashed must fail, not raise SIGPIPE and end this
            // process too.
            signal(SIGPIPE, SIG_IGN)
            do { try process.run() } catch {
                throw RendererError(description: "can't start \(executable.path): \(error)")
            }
            Self.read(outputPipe.fileHandleForReading, into: lines)
            Self.read(errorPipe.fileHandleForReading, into: errorTail)
            let first = lines.next(timeout: timeout)
            guard case .line(let line) = first else {
                Self.stop(process)
                throw RendererError(
                    description:
                        "the renderer \(first == .closed ? "exited before it started" : "didn't start within \(timeout)")\(errorTail.suffix)"
                )
            }
            guard let hello = try? JSONDecoder().decode(RendererHello.self, from: line) else {
                Self.stop(process)
                throw RendererError(description: "the renderer didn't say hello\(errorTail.suffix)")
            }
            guard hello.protocolVersion == RendererProtocol.version else {
                Self.stop(process)
                throw RendererError(
                    description:
                        "the renderer speaks protocol \(hello.protocolVersion), not \(RendererProtocol.version); it was built with SwiftBook \(hello.swiftBookVersion)"
                )
            }
            self.hello = hello
        }

        deinit {
            if process.isRunning { stop() }
        }

        /// Every story the renderer's code declares. With `check`, the renderer also builds each
        /// story's view and reports the ones that fail.
        public func stories(check: Bool = false, timeout: Duration = .seconds(120)) throws
            -> [StoryInfo]
        {
            let response = try send(.init(id: 0, method: .list, check: check), timeout: timeout)
            guard let stories = response.stories else {
                throw RendererError(description: "the renderer listed no stories")
            }
            return stories
        }

        /// Renders `story` in `environment`, returning the snapshot as PNG with its metadata.
        public func render(
            _ story: StoryID, in environment: RenderEnvironment = RenderEnvironment(),
            timeout: Duration = .seconds(30)
        ) throws -> Data {
            let response = try send(
                .init(id: 0, method: .render, story: story.description, environment: environment),
                timeout: timeout)
            guard let png = response.png else {
                throw RendererError(description: "the renderer sent no image for \(story)")
            }
            return png
        }

        /// Asks the renderer to exit, and stops it if it doesn't.
        public func shutdown(timeout: Duration = .seconds(5)) {
            _ = try? send(.init(id: 0, method: .shutdown), timeout: timeout)
            // A renderer also exits at the end of its input.
            try? input.close()
            stop(grace: timeout)
        }

        private func stop(grace: Duration = .seconds(2)) {
            Self.stop(process, grace: grace)
        }

        /// Ends `process`: asks it to terminate, and kills it if it hasn't after `grace`.
        /// Returns once it has exited.
        private static func stop(_ process: Process, grace: Duration = .seconds(2)) {
            let deadline = ContinuousClock.now + grace
            if process.isRunning { process.terminate() }
            while process.isRunning, ContinuousClock.now < deadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }

        /// Whether the renderer is still running.
        public var isRunning: Bool { process.isRunning }

        private func send(_ request: RendererRequest, timeout: Duration) throws -> RendererResponse
        {
            lock.lock()
            defer { lock.unlock() }
            guard process.isRunning else {
                throw RendererError(description: "the renderer has exited\(errorTail.suffix)")
            }
            var request = request
            request.id = nextID
            nextID += 1
            var data = try JSONEncoder().encode(request)
            data.append(0x0A)
            do { try input.write(contentsOf: data) } catch {
                throw RendererError(description: "the renderer has exited\(errorTail.suffix)")
            }
            let next = lines.next(timeout: timeout)
            guard case .line(let line) = next else {
                if next == .timedOut {
                    stop()
                    throw RendererError(
                        description:
                            "the renderer took longer than \(timeout) to \(request.method) and was stopped"
                    )
                }
                // Its output closed: it exited, or is about to.
                process.waitUntilExit()
                throw RendererError(
                    description:
                        "the renderer exited with status \(process.terminationStatus) during \(request.method)\(errorTail.suffix)"
                )
            }
            let response: RendererResponse
            do { response = try JSONDecoder().decode(RendererResponse.self, from: line) } catch {
                throw RendererError(description: "the renderer sent an unreadable response")
            }
            guard response.id == request.id else {
                throw RendererError(
                    description: "the renderer answered request \(response.id), not \(request.id)")
            }
            if let error = response.error { throw RendererError(description: error) }
            return response
        }

        // MARK: Reading output

        private protocol Sink: Sendable {
            func append(_ data: Data)
            func close()
        }

        /// Reads `handle` on its own thread until it closes.
        private static func read(_ handle: FileHandle, into sink: some Sink) {
            Thread.detachNewThread {
                while true {
                    let data = handle.availableData
                    if data.isEmpty { break }
                    sink.append(data)
                }
                sink.close()
            }
        }

        /// Complete lines of output, waited on one at a time.
        private final class LineQueue: Sink, @unchecked Sendable {
            // Unchecked: `condition` guards everything.
            private let condition = NSCondition()
            private var buffer = Data()
            private var lines: [Data] = []
            private var closed = false

            func append(_ data: Data) {
                condition.lock()
                buffer.append(data)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    lines.append(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                }
                condition.broadcast()
                condition.unlock()
            }

            func close() {
                condition.lock()
                closed = true
                condition.broadcast()
                condition.unlock()
            }

            enum Next: Equatable {
                case line(Data)
                case timedOut
                /// The output closed with no more lines.
                case closed
            }

            /// The next line, waiting at most `timeout`.
            func next(timeout: Duration) -> Next {
                let seconds =
                    Double(timeout.components.seconds)
                    + Double(timeout.components.attoseconds) / 1e18
                let deadline = Date(timeIntervalSinceNow: seconds)
                condition.lock()
                defer { condition.unlock() }
                while lines.isEmpty, !closed {
                    if !condition.wait(until: deadline) { return .timedOut }
                }
                return lines.isEmpty ? .closed : .line(lines.removeFirst())
            }
        }

        /// The end of the renderer's standard error, for explaining failures.
        private final class Tail: Sink, @unchecked Sendable {
            // Unchecked: `lock` guards `data`.
            private let lock = NSLock()
            private var data = Data()
            private let limit = 4096

            func append(_ chunk: Data) {
                lock.lock()
                data.append(chunk)
                if data.count > limit { data.removeFirst(data.count - limit) }
                lock.unlock()
            }

            func close() {}

            /// ": <text>" for appending to a message, or empty if there's nothing.
            var suffix: String {
                lock.lock()
                defer { lock.unlock() }
                let text = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "" : ". It said:\n\(text)"
            }
        }
    }
#endif
