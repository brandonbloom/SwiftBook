#if os(macOS)
    import Foundation
    import SwiftBookCore

    /// Lists and renders stories for the viewer. The real one supervises renderer processes;
    /// tests use fakes.
    protocol StoryRenderer: Sendable {
        /// Which build the renderer is serving, counting from 1.
        func generation() async -> Int
        func stories() async throws -> [StoryInfo]
        /// Renders `story`. A `background` render gets a short timeout, so a slow story can't
        /// hold up one someone is waiting for.
        func render(_ story: StoryID, in environment: RenderEnvironment, background: Bool)
            async throws -> Data
        /// Shows `story` live in a window of its own, for interacting with.
        func open(_ story: StoryID, in environment: RenderEnvironment) async throws
        /// Builds the package again and swaps to a renderer of the new build, returning its
        /// generation. Until then, the current renderer keeps serving. Interactive windows
        /// still open reopen on the new build.
        func rebuild() async throws -> Int
    }

    /// Supervises a package's renderer processes, one build generation at a time.
    ///
    /// Requests run on a queue of its own, so the viewer's main thread never waits on one. A
    /// renderer that crashes, or hangs past `renderTimeout`, is restarted from the same build:
    /// the failing request reports the problem, and later ones go to the new process. Builds run
    /// on another queue, so the current renderer keeps serving while the next generation builds.
    final class RendererSupervisor: StoryRenderer, @unchecked Sendable {
        // Unchecked: the mutable state is only touched on `queue`.

        let package: URL
        let renderTimeout: Duration
        private let queue = DispatchQueue(label: "SwiftBook renderer")
        private let buildQueue = DispatchQueue(label: "SwiftBook renderer build")
        private let build: @Sendable (URL) throws -> URL
        private var executable: URL?
        private var process: RendererProcess?
        private var currentGeneration = 0
        private let environment: [String: String]

        init(
            package: URL, renderTimeout: Duration = .seconds(30),
            build: @escaping @Sendable (URL) throws -> URL = {
                try RendererHost(package: $0).build()
            }
        ) {
            self.package = package
            self.renderTimeout = renderTimeout
            self.build = build
            environment = Self.environment(for: package)
        }

        /// Builds the package's renderer and starts it.
        static func start(for package: URL, renderTimeout: Duration = .seconds(30)) async throws
            -> RendererSupervisor
        {
            let supervisor = RendererSupervisor(package: package, renderTimeout: renderTimeout)
            _ = try await supervisor.rebuild()
            return supervisor
        }

        func generation() async -> Int {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: self.currentGeneration) }
            }
        }

        func stories() async throws -> [StoryInfo] {
            try await run { try self.running().stories() }
        }

        /// The renderer's environment. Its captures must match how the package's Mac references
        /// were recorded for comparisons to mean anything. Unless `SWIFTBOOK_CAPTURE` says
        /// otherwise, it captures from the window server if they were (and the renderer may
        /// record the screen), and emulated, as CI does, otherwise.
        static func environment(
            for package: URL,
            inherited: [String: String] = ProcessInfo.processInfo.environment
        ) -> [String: String] {
            let variable = CaptureMethod.environmentVariable
            if let method = inherited[variable], !method.isEmpty { return [variable: method] }
            let store = SnapshotStore(
                root: package.appending(path: "Snapshots", directoryHint: .isDirectory))
            if store.recordedCapture(on: .mac) == CaptureMethod.windowServer.rawValue {
                // The renderer's own choice: the window server when it can.
                return [:]
            }
            return [variable: CaptureMethod.emulated.rawValue]
        }

        /// How long a background render may take.
        static let backgroundTimeout = Duration.seconds(5)

        func render(_ story: StoryID, in environment: RenderEnvironment, background: Bool)
            async throws -> Data
        {
            try await run {
                let process = try self.running()
                let timeout = background ? Self.backgroundTimeout : self.renderTimeout
                do {
                    return try process.render(story, in: environment, timeout: timeout)
                } catch {
                    // A crash or a hang ends the process. Start another from the same build, so
                    // one bad story doesn't take the rest down with it.
                    guard !process.isRunning, let executable = self.executable else { throw error }
                    self.process = try? RendererProcess(
                        executable: executable, environment: self.environment)
                    throw RendererError(
                        description:
                            "\(error)\nThe renderer was restarted; other stories are unaffected.")
                }
            }
        }

        func open(_ story: StoryID, in environment: RenderEnvironment) async throws {
            try await run { try self.running().open(story, in: environment) }
        }

        /// The current renderer's interactive windows that are still open.
        func windows() async throws -> [RendererWindow] {
            try await run { try self.running().windows() }
        }

        func rebuild() async throws -> Int {
            // Building takes a while; the current renderer keeps serving meanwhile.
            Self.log("build started")
            let executable = try await onBuildQueue { try self.build(self.package) }
            Self.log("build finished; starting the new renderer")
            let (fresh, stories) = try await onBuildQueue {
                () -> (RendererProcess, [StoryInfo]) in
                let process = try RendererProcess(
                    executable: executable, environment: self.environment)
                Self.log("new renderer started; warming up")
                // Warm up: discovery runs on the first list, before anyone waits on it.
                return (process, try process.stories())
            }
            Self.log("new renderer warm; swapping")
            return try await run {
                let old = self.process
                self.executable = executable
                self.process = fresh
                self.currentGeneration += 1
                // Requests run on this queue, so none is using the old renderer now.
                let windows = (try? old?.windows()) ?? []
                old?.shutdown(timeout: .seconds(2))
                // Live reload for interactive windows: the new build shows them again.
                for window in windows {
                    if let story = stories.first(where: { $0.id.description == window.story }) {
                        try? fresh.open(story.id, in: window.environment)
                    }
                }
                return self.currentGeneration
            }
        }

        private static func log(_ message: String) {
            FileHandle.standardError.write(Data("swiftbook-viewer: \(message)\n".utf8))
        }

        /// The running renderer, restarted from the current build if it has exited.
        private func running() throws -> RendererProcess {
            if let process, process.isRunning { return process }
            guard let executable else {
                throw RendererError(description: "the renderer isn't running")
            }
            let restarted = try RendererProcess(
                executable: executable, environment: self.environment)
            process = restarted
            return restarted
        }

        /// Runs `body` on the request queue.
        private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T
        {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { continuation.resume(with: Result(catching: body)) }
            }
        }

        /// Runs `body` on the build queue.
        private func onBuildQueue<T: Sendable>(_ body: @escaping @Sendable () throws -> T)
            async throws -> T
        {
            try await withCheckedThrowingContinuation { continuation in
                buildQueue.async { continuation.resume(with: Result(catching: body)) }
            }
        }
    }
#endif
