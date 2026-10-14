#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook render`: renders stories to PNG files.
    struct RenderCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "render",
            abstract: "Render stories to PNG files.",
            discussion: """
                Renders each story in each appearance into the output directory, named like \
                references: <Module>/<Group>/<Story>/<device>.<appearance>.png. With no stories, \
                renders all of them. Nothing is compared or recorded, so it's the quick way to \
                look at a story, or to send someone a picture of one. swiftbook list prints \
                story names; for example, swiftbook render Wander/Welcome/Welcome --device iphone.
                """)

        @Argument(help: "Stories to render, as Module/Group/Name, as swiftbook list prints them.")
        var stories: [String] = []

        @Option(name: [.customLong("device"), .customLong("platform")], help: deviceHelp)
        var device = Device.mac

        @Option(name: .shortAndLong, help: "The directory to write PNG files to.")
        var output = ".build/swiftbook/renders"

        func run() throws {
            do {
                let project = try Project.current()
                let renderer = try Renderers.start(for: project, on: device)
                defer { renderer.shutdown() }
                let all = try renderer.stories()
                let selected =
                    stories.isEmpty
                    ? all.map(\.id)
                    : try stories.map { name in
                        guard let story = all.first(where: { $0.id.description == name }) else {
                            throw Failure(description: "no story \(name)")
                        }
                        return story.id
                    }
                let store = SnapshotStore(
                    root: URL(
                        filePath: output, directoryHint: .isDirectory,
                        relativeTo: URL(filePath: FileManager.default.currentDirectoryPath)))
                var failures = 0
                for story in selected {
                    for appearance in RenderEnvironment.Appearance.allCases {
                        var environment = RenderEnvironment.standard(for: device)
                        environment.appearance = appearance
                        let url = store.url(
                            for: story, device: device, environment: environment)
                        do {
                            let png = try renderer.render(story, in: environment)
                            try FileManager.default.createDirectory(
                                at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
                            try png.write(to: url)
                            print(url.path)
                        } catch {
                            failures += 1
                            warn("swiftbook: \(story) (\(appearance)): \(error)")
                        }
                    }
                }
                if failures > 0 { throw Exit.broken.code }
            } catch let exit as ExitCode {
                throw exit
            } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
        }
    }
#endif
