#if os(macOS)
    import Foundation
    import SwiftBookCore

    /// Lists and renders stories for the viewer. The real one supervises renderer processes;
    /// tests use fakes.
    protocol StoryRenderer: Sendable {
        /// Which build the renderer is serving, counting from 1.
        func generation() async -> Int
        func stories() async throws -> [StoryInfo]
        func render(_ story: StoryID, in environment: RenderEnvironment) async throws -> Data
        /// Builds the package again and swaps to a renderer of the new build, returning its
        /// generation. Until then, the current renderer keeps serving.
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

        init(
            package: URL, renderTimeout: Duration = .seconds(30),
            build: @escaping @Sendable (URL) throws -> URL = {
                try RendererHost(package: $0).build()
            }
        ) {
            self.package = package
            self.renderTimeout = renderTimeout
            self.build = build
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

        func render(_ story: StoryID, in environment: RenderEnvironment) async throws -> Data {
            try await run {
                let process = try self.running()
                do {
                    return try process.render(story, in: environment, timeout: self.renderTimeout)
                } catch {
                    // A crash or a hang ends the process. Start another from the same build, so
                    // one bad story doesn't take the rest down with it.
                    guard !process.isRunning, let executable = self.executable else { throw error }
                    self.process = try? RendererProcess(executable: executable)
                    throw RendererError(
                        description:
                            "\(error)\nThe renderer was restarted; other stories are unaffected.")
                }
            }
        }

        func rebuild() async throws -> Int {
            // Building takes a while; the current renderer keeps serving meanwhile.
            let executable = try await onBuildQueue { try self.build(self.package) }
            let fresh = try await onBuildQueue { () -> RendererProcess in
                let process = try RendererProcess(executable: executable)
                // Warm up: discovery runs on the first list, before anyone waits on it.
                _ = try process.stories()
                return process
            }
            return try await run {
                let old = self.process
                self.executable = executable
                self.process = fresh
                self.currentGeneration += 1
                // Requests run on this queue, so none is using the old renderer now.
                old?.shutdown(timeout: .seconds(2))
                return self.currentGeneration
            }
        }

        /// The running renderer, restarted from the current build if it has exited.
        private func running() throws -> RendererProcess {
            if let process, process.isRunning { return process }
            guard let executable else {
                throw RendererError(description: "the renderer isn't running")
            }
            let restarted = try RendererProcess(executable: executable)
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
