#if os(macOS)
    import Foundation

    /// A renderer that restarts itself when it crashes or hangs, so one bad story fails alone.
    ///
    /// A render that ends the renderer (a crash, or a hang it was stopped for) is tried once more
    /// on a fresh one: hangs can be transient, such as on a loaded machine. If it fails again,
    /// the error says so, and the next request still gets a working renderer.
    package final class RestartingRenderer: @unchecked Sendable {
        // Unchecked: `lock` guards `process` and `restarts`.

        private let start: @Sendable () throws -> RendererProcess
        private let lock = NSLock()
        private var process: RendererProcess
        /// How many times the renderer has been restarted.
        package private(set) var restarts = 0
        /// What ended each renderer that was restarted mid-render: the story, and the error.
        package private(set) var incidents: [String] = []

        /// Starts a renderer with `start`, which also starts each replacement.
        private let onShutdown: @Sendable () -> Void

        /// Starts a renderer with `start`, which also restarts it. `onShutdown` runs after
        /// ``shutdown()``, to release what the renderer used, such as its simulator.
        package init(
            start: @escaping @Sendable () throws -> RendererProcess,
            onShutdown: @escaping @Sendable () -> Void = {}
        ) throws {
            self.start = start
            self.onShutdown = onShutdown
            process = try start()
        }

        /// What the current renderer said when it started.
        package var hello: RendererHello { lock.withLock { process.hello } }

        package func stories(check: Bool = false, timeout: Duration = .seconds(120)) throws
            -> [StoryInfo]
        {
            try lock.withLock { try running().stories(check: check, timeout: timeout) }
        }

        /// Renders `story`, retrying once on a fresh renderer if the first attempt ended the
        /// renderer.
        package func render(
            _ story: StoryID, in environment: RenderEnvironment = RenderEnvironment(),
            timeout: Duration = .seconds(30)
        ) throws -> Data {
            try renderImage(story, in: environment, timeout: timeout).png
        }

        /// Like ``render(_:in:timeout:)``, with where the snapshot has glass. With `recording`,
        /// the renderer records the code the render runs.
        package func renderImage(
            _ story: StoryID, in environment: RenderEnvironment = RenderEnvironment(),
            recording: RenderRecording? = nil, timeout: Duration = .seconds(30)
        ) throws -> RenderedImage {
            try lock.withLock {
                let first = try running()
                do {
                    return try first.renderImage(
                        story, in: environment, recording: recording, timeout: timeout)
                } catch {
                    // An error the renderer reported leaves it running; that's the story's fault.
                    guard !first.isRunning else { throw error }
                    incidents.append("\(story): \(error)")
                    do {
                        return try running().renderImage(
                            story, in: environment, recording: recording, timeout: timeout)
                    } catch let retry {
                        throw RendererError(
                            description:
                                "\(retry)\nIt failed the same way on a restarted renderer: \(error)"
                        )
                    }
                }
            }
        }

        package func shutdown() {
            lock.withLock { process.shutdown() }
            onShutdown()
        }

        /// The renderer, restarted if it has exited.
        private func running() throws -> RendererProcess {
            if process.isRunning { return process }
            process = try start()
            restarts += 1
            return process
        }
    }
#endif
