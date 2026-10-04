import Foundation
import SwiftBookCore

#if os(macOS)
    import AppKit
#elseif os(iOS) || os(tvOS)
    import UIKit
#endif

/// A renderer process: serves ``RendererProtocol`` to the SwiftBook tool that started it.
///
/// The host package's executable calls ``main()``. The user's code links into the same process,
/// so its stories are discovered at runtime, as under `swift test`. On macOS the protocol runs
/// over standard input and output. On iOS and tvOS, where the app runs in a simulator, it runs
/// over a TCP connection to the port in `SWIFTBOOK_RENDERER_PORT` on the host.
public enum RendererServer {
    /// The variable that gives an iOS or tvOS renderer the port to connect to.
    public static let portVariable = "SWIFTBOOK_RENDERER_PORT"

    #if os(macOS)
        /// Serves requests until `shutdown` or the end of input, then exits.
        public static func main() -> Never {
            // The protocol keeps the real standard output. Anything else that prints, such as
            // the user's code, goes to standard error instead of corrupting the stream.
            let output = FileHandle(fileDescriptor: dup(STDOUT_FILENO))
            dup2(STDERR_FILENO, STDOUT_FILENO)
            MainActor.assumeIsolated {
                // A renderer never shows anything or takes focus.
                _ = NSApplication.shared.setActivationPolicy(.prohibited)
            }
            serve(input: .standardInput, output: output)
            // Rendering needs the main run loop: AppKit and SwiftUI update through it.
            while true { RunLoop.main.run() }
        }
    #elseif os(iOS) || os(tvOS)
        /// Runs the renderer app, which connects back and serves requests until `shutdown`.
        public static func main() -> Never {
            UIApplicationMain(
                CommandLine.argc, CommandLine.unsafeArgv, nil,
                NSStringFromClass(RendererAppDelegate.self))
            exit(0)
        }

        /// Connects to the tool and serves it, once the app has a window scene to render in.
        @MainActor static func connect() {
            guard let port = ProcessInfo.processInfo.environment[portVariable].flatMap(UInt16.init)
            else {
                FileHandle.standardError.write(Data("swiftbook: no \(portVariable)\n".utf8))
                exit(2)
            }
            guard let socket = Self.socket(toLocalPort: port) else {
                FileHandle.standardError.write(
                    Data("swiftbook: can't connect to port \(port)\n".utf8))
                exit(2)
            }
            let handle = FileHandle(fileDescriptor: socket, closeOnDealloc: true)
            serve(input: handle, output: handle)
        }

        /// A TCP connection to `port` on the loopback interface, which the simulator shares with
        /// the host.
        private static func socket(toLocalPort port: UInt16) -> Int32? {
            let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return nil }
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard connected == 0 else {
                close(descriptor)
                return nil
            }
            return descriptor
        }
    #endif

    /// Sends the hello, then answers each line of `input` on the main actor, in order, and exits
    /// after `shutdown` or the end of input.
    static func serve(input: FileHandle, output: FileHandle) {
        let channel = Channel(output: output)
        channel.send(
            RendererHello(
                protocolVersion: RendererProtocol.version,
                swiftBookVersion: SwiftBookInfo.version, platform: Server.platform))
        let (requests, continuation) = AsyncStream.makeStream(of: Data.self)
        Thread.detachNewThread {
            var buffer = Data()
            while true {
                let chunk = input.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    continuation.yield(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                }
            }
            continuation.finish()
        }
        Task { @MainActor in
            let server = Server(channel: channel)
            for await line in requests {
                guard await server.handle(Data(line)) else { break }
            }
            exit(0)
        }
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
        nonisolated static var platform: String {
            #if os(macOS)
                "macOS"
            #elseif os(tvOS)
                "tvOS"
            #else
                "iOS"
            #endif
        }

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
            guard let request = try? JSONDecoder().decode(RendererRequest.self, from: line) else {
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
                #if os(macOS)
                    let snapshot = try await MacRenderer.render(
                        story, in: request.environment ?? RenderEnvironment())
                #else
                    let snapshot = try await UIKitRenderer.render(
                        story,
                        in: request.environment ?? .standard(for: UIKitRenderer.device))
                #endif
                return RendererResponse(id: request.id, png: try snapshot.pngData())
            } catch {
                return RendererResponse(id: request.id, error: String(describing: error))
            }
        }
    }
}

#if os(iOS) || os(tvOS)
    /// The renderer app's delegate: gives it one scene, whose delegate starts serving.
    final class RendererAppDelegate: UIResponder, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            configurationForConnecting connectingSceneSession: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(
                name: nil, sessionRole: connectingSceneSession.role)
            configuration.delegateClass = RendererSceneDelegate.self
            return configuration
        }

        #if os(iOS)
            func application(
                _ application: UIApplication,
                supportedInterfaceOrientationsFor window: UIWindow?
            ) -> UIInterfaceOrientationMask {
                RendererOrientation.allowed
            }
        #endif
    }

    final class RendererSceneDelegate: UIResponder, UIWindowSceneDelegate {
        var window: UIWindow?

        func scene(
            _ scene: UIScene, willConnectTo session: UISceneSession,
            options connectionOptions: UIScene.ConnectionOptions
        ) {
            guard let scene = scene as? UIWindowScene else { return }
            // A blank window keeps the scene in the foreground while stories render in others.
            let window = UIWindow(windowScene: scene)
            window.rootViewController = UIViewController()
            window.makeKeyAndVisible()
            self.window = window
            RendererServer.connect()
        }
    }
#endif
