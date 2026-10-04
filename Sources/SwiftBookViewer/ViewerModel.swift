#if os(macOS)
    import AppKit
    import Foundation
    import Observation
    import SwiftBookCore

    /// A node of the sidebar's story tree: a module, a group (usually a file), or a story.
    struct StoryNode: Identifiable, Hashable {
        /// `Module`, `Module/Group`, or the story's full ID.
        let id: String
        let title: String
        /// The story, for a leaf.
        let story: StoryID?
        /// Modules and groups have children; stories don't.
        let children: [StoryNode]?

        /// Modules, then groups, then stories, each in the order the renderer listed them.
        static func tree(_ stories: [StoryInfo]) -> [StoryNode] {
            var modules: [String] = []
            var groups: [String: [String]] = [:]
            var leaves: [String: [StoryID]] = [:]
            for story in stories {
                let id = story.id
                let group = "\(id.module)/\(id.group)"
                if groups[id.module] == nil {
                    modules.append(id.module)
                    groups[id.module] = []
                }
                if leaves[group] == nil {
                    groups[id.module]!.append(group)
                    leaves[group] = []
                }
                leaves[group]!.append(id)
            }
            return modules.map { module in
                StoryNode(
                    id: module, title: module, story: nil,
                    children: groups[module]!.map { group in
                        StoryNode(
                            id: group, title: String(group.dropFirst(module.count + 1)), story: nil,
                            children: leaves[group]!.map {
                                StoryNode(
                                    id: $0.description, title: $0.name, story: $0, children: nil)
                            })
                    })
            }
        }
    }

    /// What the viewer shows, and what it's waiting on.
    @Observable @MainActor final class ViewerModel {
        enum Status: Equatable {
            /// Building the package's renderer.
            case building
            /// Asking the renderer for its stories.
            case listing
            case ready
            case failed(String)
        }

        /// A render of one story in one environment.
        enum Render: Equatable {
            case rendering
            case image(NSImage)
            case failed(String)
        }

        struct RenderKey: Hashable {
            let story: StoryID
            let appearance: RenderEnvironment.Appearance
        }

        let package: URL
        private(set) var status = Status.building {
            didSet { log("\(status)") }
        }
        private(set) var stories: [StoryInfo] = []
        private(set) var tree: [StoryNode] = []
        var selection: StoryID? {
            didSet { renderSelection() }
        }
        var appearance = RenderEnvironment.Appearance.light {
            didSet { renderSelection() }
        }
        private(set) var renders: [RenderKey: Render] = [:]

        private var renderer: (any StoryRenderer)?
        private let startRenderer: @Sendable (URL) async throws -> any StoryRenderer

        init(
            package: URL,
            startRenderer: @escaping @Sendable (URL) async throws -> any StoryRenderer = {
                try await ProcessStoryRenderer.start(for: $0)
            }
        ) {
            self.package = package
            self.startRenderer = startRenderer
        }

        /// Builds and starts the renderer, lists stories, and selects the first.
        func start() async {
            log("starting on \(package.path)")
            status = .building
            do {
                let renderer = try await startRenderer(package)
                self.renderer = renderer
                status = .listing
                stories = try await renderer.stories()
                tree = StoryNode.tree(stories)
                status = .ready
                if selection == nil { selection = stories.first?.id }
            } catch {
                status = .failed(String(describing: error))
            }
        }

        /// The render the canvas shows: the selection in the chosen appearance.
        var currentRender: Render? {
            selection.flatMap { renders[RenderKey(story: $0, appearance: appearance)] }
        }

        private func renderSelection() {
            guard let story = selection, let renderer else { return }
            let key = RenderKey(story: story, appearance: appearance)
            guard renders[key] == nil else { return }
            renders[key] = .rendering
            var environment = RenderEnvironment()
            environment.appearance = appearance
            Task {
                do {
                    let png = try await renderer.render(story, in: environment)
                    guard let image = NSImage(data: png) else {
                        renders[key] = .failed("the renderer sent an unreadable image")
                        return
                    }
                    // The bitmap is at the render's scale; show it at its size in points.
                    if let representation = image.representations.first {
                        image.size = CGSize(
                            width: Double(representation.pixelsWide) / environment.scale,
                            height: Double(representation.pixelsHigh) / environment.scale)
                    }
                    renders[key] = .image(image)
                    log("rendered \(story) (\(appearance))")
                } catch {
                    renders[key] = .failed(String(describing: error))
                }
            }
        }

        /// What the viewer is showing, for checks that can't see the window.
        struct Summary: Codable, Equatable {
            var status: String
            var stories: Int
            var groups: [String]
            var selection: String?
            var render: String?
        }

        var summary: Summary {
            Summary(
                status: "\(status)", stories: stories.count,
                groups: tree.flatMap { $0.children ?? [] }.map(\.id),
                selection: selection?.description,
                render: currentRender.map {
                    switch $0 {
                    case .rendering: "rendering"
                    case .image(let image):
                        "image \(Int(image.size.width))×\(Int(image.size.height))"
                    case .failed(let message): "failed: \(message)"
                    }
                })
        }

        /// Writes a line to standard error, which `swiftbook view` sends to the viewer's log.
        private func log(_ message: String) {
            FileHandle.standardError.write(Data("swiftbook-viewer: \(message)\n".utf8))
        }
    }
#endif
