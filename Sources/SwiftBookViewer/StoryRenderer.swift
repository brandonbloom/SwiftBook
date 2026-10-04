#if os(macOS)
    import Foundation
    import SwiftBookCore

    /// Lists and renders stories for the viewer. The real one is a renderer process; tests use
    /// fakes.
    protocol StoryRenderer: Sendable {
        func stories() async throws -> [StoryInfo]
        func render(_ story: StoryID, in environment: RenderEnvironment) async throws -> Data
        func shutdown() async
    }

    /// A renderer process for a package, driven from a queue of its own, so the viewer's main
    /// thread never waits on a build or a render.
    final class ProcessStoryRenderer: StoryRenderer, @unchecked Sendable {
        // Unchecked: `process` is only touched on `queue`.

        private let queue = DispatchQueue(label: "SwiftBook renderer")
        private var process: RendererProcess?

        /// Builds the package's renderer and starts it.
        static func start(for package: URL) async throws -> ProcessStoryRenderer {
            let renderer = ProcessStoryRenderer()
            try await renderer.run {
                let executable = try RendererHost(package: package).build()
                renderer.process = try RendererProcess(executable: executable)
            }
            return renderer
        }

        func stories() async throws -> [StoryInfo] {
            try await run { try self.started().stories() }
        }

        func render(_ story: StoryID, in environment: RenderEnvironment) async throws -> Data {
            try await run { try self.started().render(story, in: environment) }
        }

        func shutdown() async {
            try? await run { self.process?.shutdown() }
        }

        private func started() throws -> RendererProcess {
            guard let process else {
                throw RendererError(description: "the renderer isn't running")
            }
            return process
        }

        /// Runs `body` on the renderer's queue.
        private func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T
        {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { continuation.resume(with: Result(catching: body)) }
            }
        }
    }
#endif
