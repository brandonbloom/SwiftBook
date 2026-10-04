#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook list`: lists the package's stories, as a renderer discovers them.
    struct ListCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List the package's stories.",
            discussion: """
                Builds a renderer that links the package's library products, and asks it for \
                every story. Exits with status \(Exit.broken.rawValue) if --check finds a story \
                SwiftBook can't read.
                """)

        @Flag(help: "Also build each story's view, and report the ones that fail.")
        var check = false

        @Option(help: "The platform to discover stories on: macos, ios, or tvos.")
        var platform = Platform.macOS

        @Flag(help: "Print the stories as JSON.")
        var json = false

        func run() throws {
            let stories: [StoryInfo]
            do {
                let renderer = try Renderers.start(for: try Project.current(), on: platform)
                defer { renderer.shutdown() }
                stories = try renderer.stories(check: check)
            } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(stories), as: UTF8.self))
            } else {
                for story in stories {
                    print(story.id.description + (story.error.map { "  ✗ \($0)" } ?? ""))
                }
            }
            if stories.contains(where: { $0.error != nil }) { throw Exit.broken.code }
        }
    }

    /// A platform SwiftBook renders on.
    enum Platform: String, ExpressibleByArgument, CaseIterable, Sendable {
        case macOS = "macos"
        case iOS = "ios"
        case tvOS = "tvos"

        /// The device class it renders as.
        var device: Device {
            switch self {
            case .macOS: .mac
            case .iOS: .iphone
            case .tvOS: .tv
            }
        }
    }

    /// Starting renderers for the CLI.
    enum Renderers {
        /// Builds the renderer for `project` on `platform` and starts it, in SwiftBook's own
        /// simulator for iOS and tvOS.
        static func start(for project: Project, on platform: Platform = .macOS) throws
            -> RendererProcess
        {
            let host = RendererHost(package: project.root)
            switch platform {
            case .macOS:
                progress("Building the renderer…")
                return try RendererProcess(executable: host.build())
            case .iOS, .tvOS:
                progress("Building the \(platform.device) renderer…")
                let app = try host.buildApp(for: platform == .iOS ? .iOS : .tvOS)
                progress("Starting the simulator…")
                let simulator = try Simulator.dedicated(for: platform.device)
                return try RendererProcess(app: app.url, bundleID: app.bundleID, in: simulator)
            }
        }

        private static func progress(_ message: String) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
    }
#endif
