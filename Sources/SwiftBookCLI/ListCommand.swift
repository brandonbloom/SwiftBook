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

        @Flag(help: "Print the stories as JSON.")
        var json = false

        func run() throws {
            let stories: [StoryInfo]
            do {
                let renderer = try Renderers.start(for: try Project.current())
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

    /// Starting renderers for the CLI.
    enum Renderers {
        /// Builds the renderer for `project` and starts it. Build output goes to standard error
        /// when it fails.
        static func start(for project: Project) throws -> RendererProcess {
            FileHandle.standardError.write(Data("Building the renderer…\n".utf8))
            let executable = try RendererHost(package: project.root).build()
            return try RendererProcess(executable: executable)
        }
    }
#endif
