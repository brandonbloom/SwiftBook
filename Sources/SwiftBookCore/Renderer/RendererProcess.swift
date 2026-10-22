#if os(macOS)
    import Foundation

    /// A renderer failed: it couldn't start, crashed, hung, or reported an error.
    public struct RendererError: Error, CustomStringConvertible, Sendable {
        public let description: String

        public init(description: String) {
            self.description = description
        }
    }

    /// A running renderer, spoken to over ``RendererProtocol``: a local process for macOS, or an
    /// app in a simulator for iOS and tvOS.
    ///
    /// Requests are answered one at a time, in order. A request that outlives its timeout stops
    /// the renderer; a crashed or stopped renderer fails every later request.
    public final class RendererProcess: @unchecked Sendable {
        // Unchecked: `lock` guards the mutable state.

        /// What the renderer said when it started.
        public let hello: RendererHello
        private let child: Child
        private let input: FileHandle
        /// Whether `input` is a socket, which is also the renderer's output.
        private let isSocket: Bool
        private let lines: LineQueue
        private let lock = NSLock()
        private var nextID = 1

        /// Starts `executable` and waits for its hello. `environment` adds to this process's.
        public convenience init(
            executable: URL, environment: [String: String] = [:], timeout: Duration = .seconds(60)
        ) throws {
            let process = Process()
            process.executableURL = executable
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            Self.ignoreBrokenPipes()
            do { try process.run() } catch {
                throw RendererError(description: "can't start \(executable.path): \(error)")
            }
            let lines = LineQueue()
            let errorTail = Tail()
            Self.read(outputPipe.fileHandleForReading, into: lines)
            Self.read(errorPipe.fileHandleForReading, into: errorTail)
            try self.init(
                child: Child(process: process, errorTail: errorTail),
                input: inputPipe.fileHandleForWriting, isSocket: false, lines: lines,
                timeout: timeout)
        }

        /// Installs and launches the renderer app at `app` in `simulator`, and waits for it to
        /// connect and say hello. `environment` is passed to the app.
        public convenience init(
            app: URL, bundleID: String, in simulator: Simulator,
            environment: [String: String] = [:], timeout: Duration = .seconds(60)
        ) throws {
            Self.ignoreBrokenPipes()
            let listener = try Listener()
            try simulator.install(app)
            let errorLog = FileManager.default.temporaryDirectory.appending(
                path: "swiftbook-renderer-\(UUID()).log")
            let pid = try simulator.launch(
                bundleID: bundleID,
                environment: environment.merging([
                    "SWIFTBOOK_RENDERER_PORT": String(listener.port)
                ]) { $1 },
                errorLog: errorLog)
            let child = Child(pid: pid, errorLog: errorLog)
            guard let connection = listener.accept(timeout: timeout, while: child.isRunning)
            else {
                child.stop(.seconds(2))
                throw RendererError(
                    description:
                        "the renderer app didn't connect within \(timeout)\(child.errorSuffix())")
            }
            let lines = LineQueue()
            Self.read(connection, into: lines)
            try self.init(
                child: child, input: connection, isSocket: true, lines: lines, timeout: timeout)
        }

        private init(
            child: Child, input: FileHandle, isSocket: Bool, lines: LineQueue, timeout: Duration
        ) throws {
            self.child = child
            self.input = input
            self.isSocket = isSocket
            self.lines = lines
            let first = lines.next(timeout: timeout)
            guard case .line(let line) = first else {
                child.stop(.seconds(2))
                throw RendererError(
                    description:
                        "the renderer \(first == .closed ? "exited before it started" : "didn't start within \(timeout)")\(child.errorSuffix())"
                )
            }
            guard let hello = try? JSONDecoder().decode(RendererHello.self, from: line) else {
                child.stop(.seconds(2))
                throw RendererError(
                    description: "the renderer didn't say hello\(child.errorSuffix())")
            }
            guard hello.protocolVersion == RendererProtocol.version else {
                child.stop(.seconds(2))
                throw RendererError(
                    description:
                        "the renderer speaks protocol \(hello.protocolVersion), not \(RendererProtocol.version); it was built with SwiftBook \(hello.swiftBookVersion)"
                )
            }
            self.hello = hello
        }

        deinit {
            if child.isRunning() { child.stop(.seconds(2)) }
        }

        /// Writing to a renderer that crashed must fail, not raise SIGPIPE and end this process
        /// too.
        private static func ignoreBrokenPipes() {
            signal(SIGPIPE, SIG_IGN)
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
            try renderImage(story, in: environment, timeout: timeout).png
        }

        /// Renders `story` in `environment`, returning the snapshot and where it has glass. With
        /// `recording`, the renderer records the code the render runs.
        public func renderImage(
            _ story: StoryID, in environment: RenderEnvironment = RenderEnvironment(),
            recording: RenderRecording? = nil, timeout: Duration = .seconds(30)
        ) throws -> RenderedImage {
            let response = try send(
                .init(
                    id: 0, method: .render, story: story.description, environment: environment,
                    recording: recording),
                timeout: timeout)
            guard let png = response.png else {
                throw RendererError(description: "the renderer sent no image for \(story)")
            }
            return RenderedImage(png: png, glassRegions: response.glassRegions ?? [])
        }

        /// Shows `story` in `environment` in a window of its own, live and interactive.
        public func open(
            _ story: StoryID, in environment: RenderEnvironment = RenderEnvironment(),
            timeout: Duration = .seconds(30)
        ) throws {
            _ = try send(
                .init(id: 0, method: .open, story: story.description, environment: environment),
                timeout: timeout)
        }

        /// The interactive windows still open.
        public func windows(timeout: Duration = .seconds(10)) throws -> [RendererWindow] {
            try send(.init(id: 0, method: .windows), timeout: timeout).windows ?? []
        }

        /// Asks the renderer to exit, and stops it if it doesn't.
        public func shutdown(timeout: Duration = .seconds(5)) {
            _ = try? send(.init(id: 0, method: .shutdown), timeout: timeout)
            // A renderer also exits at the end of its input. Only the writing half closes: a
            // socket's reader is still using the descriptor.
            Darwin.shutdown(input.fileDescriptor, SHUT_WR)
            if !isSocket { try? input.close() }
            child.stop(timeout)
        }

        /// The renderer's process ID.
        public var processIdentifier: pid_t { child.pid }

        /// Whether the renderer is still running.
        public var isRunning: Bool { child.isRunning() }

        private func send(_ request: RendererRequest, timeout: Duration) throws -> RendererResponse
        {
            lock.lock()
            defer { lock.unlock() }
            guard child.isRunning() else {
                throw RendererError(description: "the renderer has exited\(child.errorSuffix())")
            }
            var request = request
            request.id = nextID
            nextID += 1
            var data = try JSONEncoder().encode(request)
            data.append(0x0A)
            do { try input.write(contentsOf: data) } catch {
                throw RendererError(description: "the renderer has exited\(child.errorSuffix())")
            }
            let next = lines.next(timeout: timeout)
            guard case .line(let line) = next else {
                if next == .timedOut {
                    // Where it's stuck, for whoever has to find out why.
                    let sample = child.sample()
                    child.stop(.seconds(2))
                    throw RendererError(
                        description:
                            "the renderer took longer than \(timeout) to \(request.method)\(request.story.map { " \($0)" } ?? "") and was stopped"
                            + (sample.map { ". Its threads, sampled: \($0.path)" } ?? "")
                    )
                }
                // Its output closed: it exited, or is about to.
                throw RendererError(
                    description:
                        "the renderer \(child.exitDescription()) during \(request.method)\(child.errorSuffix())"
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

        // MARK: The renderer's process

        /// The renderer's process: started here, or an app the simulator started.
        private struct Child: Sendable {
            let pid: pid_t
            let isRunning: @Sendable () -> Bool
            /// Asks it to terminate, kills it if it hasn't after the grace period, and returns
            /// once it has exited.
            let stop: @Sendable (_ grace: Duration) -> Void
            /// How it ended, such as "exited with status 6", once its output has closed.
            let exitDescription: @Sendable () -> String
            /// What it last wrote to standard error.
            let errorText: @Sendable () -> String

            /// Samples the process's threads for two seconds into a file, and returns it.
            func sample() -> URL? {
                guard isRunning() else { return nil }
                let file = FileManager.default.temporaryDirectory.appending(
                    path: "swiftbook-renderer-\(pid)-\(UUID().uuidString.prefix(8)).sample.txt")
                guard
                    Shell.run(["sample", String(pid), "2", "-file", file.path])?.succeeded == true
                else { return nil }
                return file
            }

            func errorSuffix() -> String {
                let text = errorText().trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? "" : ". It said:\n\(text.suffix(4096))"
            }

            init(process: Process, errorTail: Tail) {
                pid = process.processIdentifier
                // Never `waitUntilExit`: off the main thread it can wait forever for Foundation
                // to notice an exit. Poll, with deadlines, instead.
                isRunning = { process.isRunning }
                stop = { grace in
                    Child.stop(pid: process.processIdentifier, grace: grace) { process.isRunning }
                }
                exitDescription = {
                    let deadline = ContinuousClock.now + .seconds(2)
                    while process.isRunning, ContinuousClock.now < deadline { usleep(10_000) }
                    return process.isRunning
                        ? "stopped responding" : "exited with status \(process.terminationStatus)"
                }
                errorText = { errorTail.text }
            }

            /// An app process the simulator launched. It isn't this process's child, so its exit
            /// status is unknown; its standard error goes to `errorLog`.
            ///
            /// Once it exits, macOS can give its pid to another process, so this checks that the
            /// pid still names the app before signalling it. Otherwise stopping a renderer that
            /// had already exited could kill an unrelated process.
            init(pid: pid_t, errorLog: URL) {
                self.pid = pid
                let identity = ProcessIdentity(pid: pid)
                let isRunning: @Sendable () -> Bool = { identity?.isRunning == true }
                self.isRunning = isRunning
                stop = { grace in Child.stop(pid: pid, grace: grace, isRunning: isRunning) }
                exitDescription = { "app exited" }
                errorText = {
                    (try? String(contentsOf: errorLog, encoding: .utf8)).map {
                        String($0.suffix(4096))
                    }
                        ?? ""
                }
            }

            private static func stop(
                pid: pid_t, grace: Duration, isRunning: @Sendable () -> Bool
            ) {
                guard isRunning() else { return }
                kill(pid, SIGTERM)
                let deadline = ContinuousClock.now + grace
                while isRunning(), ContinuousClock.now < deadline { usleep(10_000) }
                if isRunning() { kill(pid, SIGKILL) }
                while isRunning(), ContinuousClock.now < deadline + .seconds(2) { usleep(10_000) }
            }
        }

        /// A TCP listener on the loopback interface, which simulators share with the host.
        private struct Listener {
            let descriptor: Int32
            let port: UInt16

            init() throws {
                let descriptor = socket(AF_INET, SOCK_STREAM, 0)
                guard descriptor >= 0 else {
                    throw RendererError(description: "can't open a socket for the renderer")
                }
                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = 0
                address.sin_addr.s_addr = inet_addr("127.0.0.1")
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let bound = withUnsafeMutablePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        bind(descriptor, $0, length) == 0 && listen(descriptor, 1) == 0
                            && getsockname(descriptor, $0, &length) == 0
                    }
                }
                guard bound else {
                    close(descriptor)
                    throw RendererError(description: "can't listen for the renderer")
                }
                self.descriptor = descriptor
                port = UInt16(bigEndian: address.sin_port)
            }

            /// The first connection, or `nil` if none comes within `timeout` or while
            /// `isAlive` holds. Closes the listener either way.
            func accept(timeout: Duration, while isAlive: () -> Bool) -> FileHandle? {
                defer { close(descriptor) }
                let deadline = ContinuousClock.now + timeout
                while ContinuousClock.now < deadline, isAlive() {
                    var poller = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                    if poll(&poller, 1, 100) > 0 {
                        let connection = Darwin.accept(descriptor, nil, nil)
                        if connection >= 0 {
                            return FileHandle(fileDescriptor: connection, closeOnDealloc: true)
                        }
                    }
                }
                return nil
            }
        }

        // MARK: Reading output

        private protocol Sink: Sendable {
            func append(_ data: Data)
            func close()
        }

        /// Reads `handle` on its own thread until it closes.
        private static func read(_ handle: FileHandle, into sink: some Sink) {
            // POSIX reads, because FileHandle raises an exception if the descriptor closes
            // while it's reading.
            let descriptor = handle.fileDescriptor
            Thread.detachNewThread {
                // Keeps the descriptor open until reading ends.
                withExtendedLifetime(handle) {
                    var buffer = [UInt8](repeating: 0, count: 65536)
                    while true {
                        let count = buffer.withUnsafeMutableBytes {
                            Darwin.read(descriptor, $0.baseAddress, $0.count)
                        }
                        if count < 0, errno == EINTR { continue }
                        if count <= 0 { break }
                        sink.append(Data(buffer[0..<count]))
                    }
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

            var text: String {
                lock.lock()
                defer { lock.unlock() }
                return String(decoding: data, as: UTF8.self)
            }
        }
    }
#endif
