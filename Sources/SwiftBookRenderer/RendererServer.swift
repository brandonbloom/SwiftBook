#if os(macOS)
    import AppKit
    import Foundation
    import SwiftBookCore

    /// A renderer process: serves ``RendererProtocol`` on standard input and output.
    ///
    /// The host package's executable calls ``main()``. The user's code links into the same
    /// process, so its stories are discovered at runtime, as under `swift test`.
    public enum RendererServer {
        /// Serves requests until `shutdown` or the end of input, then exits.
        public static func main() -> Never {
            // The protocol keeps the real standard output. Anything else that prints, such as
            // the user's code, goes to standard error instead of corrupting the stream.
            let protocolOutput = FileHandle(fileDescriptor: dup(STDOUT_FILENO))
            dup2(STDERR_FILENO, STDOUT_FILENO)
            let channel = Channel(output: protocolOutput)

            MainActor.assumeIsolated {
                // A renderer never shows anything or takes focus.
                _ = NSApplication.shared.setActivationPolicy(.prohibited)
            }
            channel.send(
                RendererHello(
                    protocolVersion: RendererProtocol.version,
                    swiftBookVersion: SwiftBookInfo.version, platform: "macOS"))

            let (requests, continuation) = AsyncStream.makeStream(of: Data.self)
            Thread.detachNewThread {
                while let line = readLine(strippingNewline: true) {
                    continuation.yield(Data(line.utf8))
                }
                continuation.finish()
            }
            Task { @MainActor in
                let server = Server(channel: channel)
                for await line in requests {
                    guard await server.handle(line) else { break }
                }
                exit(0)
            }
            // Rendering needs the main run loop: AppKit and SwiftUI update through it.
            while true { RunLoop.main.run() }
        }

        /// Writes messages to the client, one JSON object per line.
        final class Channel: Sendable {
            private let output: FileHandle

            init(output: FileHandle) {
                self.output = output
            }

            func send(_ message: some Encodable) {
                guard var data = try? JSONEncoder().encode(message) else { return }
                data.append(0x0A)
                output.write(data)
            }
        }

        @MainActor final class Server {
            let channel: Channel
            /// Every story in source order, discovered on first use.
            private lazy var ordered: [Story] = Story.all()
            private lazy var stories: [String: Story] = Dictionary(
                ordered.map { ($0.id.description, $0) }, uniquingKeysWith: { first, _ in first })

            init(channel: Channel) {
                self.channel = channel
            }

            /// Answers one request. Returns `false` once the client asks to shut down.
            func handle(_ line: Data) async -> Bool {
                guard let request = try? JSONDecoder().decode(RendererRequest.self, from: line)
                else {
                    channel.send(RendererResponse(id: -1, error: "malformed request"))
                    return true
                }
                switch request.method {
                case .shutdown:
                    channel.send(RendererResponse(id: request.id))
                    return false
                case .list:
                    var infos: [StoryInfo] = []
                    for story in ordered {
                        var error: String?
                        if request.check == true {
                            do { _ = try await story.makeView() } catch let failure {
                                error = String(describing: failure)
                            }
                        }
                        infos.append(StoryInfo(story: story, error: error))
                    }
                    channel.send(RendererResponse(id: request.id, stories: infos))
                case .render:
                    channel.send(await render(request))
                }
                return true
            }

            private func render(_ request: RendererRequest) async -> RendererResponse {
                guard let id = request.story, let story = stories[id] else {
                    return RendererResponse(
                        id: request.id, error: "no story \(request.story ?? "(none)")")
                }
                do {
                    let snapshot = try await MacRenderer.render(
                        story, in: request.environment ?? RenderEnvironment())
                    return RendererResponse(id: request.id, png: try snapshot.pngData())
                } catch {
                    return RendererResponse(id: request.id, error: String(describing: error))
                }
            }
        }
    }
#endif
