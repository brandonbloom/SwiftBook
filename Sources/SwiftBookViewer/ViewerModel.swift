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
            /// The first build failed, so there's nothing to show.
            case failed(String)
        }

        /// The result of rendering one story in one environment.
        enum Render: Equatable {
            case image(NSImage)
            case failed(String)
        }

        struct RenderKey: Hashable {
            let story: StoryID
            let appearance: RenderEnvironment.Appearance
        }

        /// A render, and the build generation it came from.
        struct Rendered: Equatable {
            let render: Render
            let generation: Int
        }

        let package: URL
        private(set) var status = Status.building {
            didSet { log("\(status)") }
        }
        /// The build generation being shown.
        private(set) var generation = 0
        /// Whether a rebuild is under way. The current renders stay up meanwhile.
        private(set) var isRebuilding = false
        /// Why the last rebuild failed, until one succeeds. The last good renders stay up.
        private(set) var buildError: String?
        private(set) var stories: [StoryInfo] = []
        private(set) var tree: [StoryNode] = []
        var selection: StoryID? {
            didSet { renderSelection() }
        }
        var appearance = RenderEnvironment.Appearance.light {
            didSet { renderSelection() }
        }
        private(set) var renders: [RenderKey: Rendered] = [:]
        /// Renders requested and not yet back.
        private(set) var pending: Set<RenderKey> = []

        private var renderer: (any StoryRenderer)?
        private let startRenderer: @Sendable (URL) async throws -> any StoryRenderer

        init(
            package: URL,
            startRenderer: @escaping @Sendable (URL) async throws -> any StoryRenderer = {
                try await RendererSupervisor.start(for: $0)
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
                generation = await renderer.generation()
                status = .listing
                try await listStories()
                status = .ready
                if selection == nil { selection = stories.first?.id }
            } catch {
                status = .failed(String(describing: error))
            }
        }

        /// Builds the package again and shows the new build's stories. Until then, and if the
        /// build fails, the current renders stay up.
        func reload() async {
            guard let renderer, !isRebuilding else { return }
            isRebuilding = true
            defer { isRebuilding = false }
            log("rebuilding")
            do {
                generation = try await renderer.rebuild()
                try await listStories()
                buildError = nil
                log("generation \(generation)")
                if let selection, !stories.contains(where: { $0.id == selection }) {
                    self.selection = stories.first?.id
                } else {
                    renderSelection()
                }
            } catch {
                buildError = String(describing: error)
                log("rebuild failed")
            }
        }

        private func listStories() async throws {
            guard let renderer else { return }
            stories = try await renderer.stories()
            tree = StoryNode.tree(stories)
        }

        private var currentKey: RenderKey? {
            selection.map { RenderKey(story: $0, appearance: appearance) }
        }

        /// The render the canvas shows: the selection in the chosen appearance, possibly from an
        /// earlier generation while the current one renders.
        var currentRender: Render? {
            currentKey.flatMap { renders[$0]?.render }
        }

        /// Whether the canvas is waiting on a render of the selection.
        var isRenderingSelection: Bool {
            currentKey.map(pending.contains) ?? false
        }

        private func renderSelection() {
            guard let key = currentKey, let renderer else { return }
            // Each story renders once per generation and appearance.
            if let rendered = renders[key], rendered.generation >= generation { return }
            guard !pending.contains(key) else { return }
            pending.insert(key)
            var environment = RenderEnvironment()
            environment.appearance = key.appearance
            let generation = generation
            Task {
                defer {
                    pending.remove(key)
                    // A rebuild may have finished while this rendered.
                    if key == currentKey { renderSelection() }
                }
                let render: Render
                do {
                    let png = try await renderer.render(key.story, in: environment)
                    if let image = NSImage(data: png) {
                        // The bitmap is at the render's scale; show it at its size in points.
                        if let representation = image.representations.first {
                            image.size = CGSize(
                                width: Double(representation.pixelsWide) / environment.scale,
                                height: Double(representation.pixelsHigh) / environment.scale)
                        }
                        render = .image(image)
                        log("rendered \(key.story) (\(key.appearance))")
                    } else {
                        render = .failed("the renderer sent an unreadable image")
                    }
                } catch {
                    render = .failed(String(describing: error))
                }
                // Keep a newer render if one already arrived.
                if (renders[key]?.generation ?? 0) <= generation {
                    renders[key] = Rendered(render: render, generation: generation)
                }
            }
        }

        /// What the viewer is showing, for checks that can't see the window.
        struct Summary: Codable, Equatable {
            var status: String
            var generation: Int
            var stories: Int
            var groups: [String]
            var selection: String?
            var render: String?
            var buildError: String?
        }

        var summary: Summary {
            Summary(
                status: "\(status)", generation: generation, stories: stories.count,
                groups: tree.flatMap { $0.children ?? [] }.map(\.id),
                selection: selection?.description,
                render: currentRender.map {
                    switch $0 {
                    case .image(let image):
                        "image \(Int(image.size.width))×\(Int(image.size.height))"
                    case .failed(let message): "failed: \(message)"
                    }
                } ?? (isRenderingSelection ? "rendering" : nil),
                buildError: buildError)
        }

        /// Writes a line to standard error, which `swiftbook view` sends to the viewer's log.
        private func log(_ message: String) {
            FileHandle.standardError.write(Data("swiftbook-viewer: \(message)\n".utf8))
        }
    }
#endif
