#if os(macOS)
    import AppKit
    import Foundation
    import Observation
    import SwiftBookCore
    import SwiftUI

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
            /// The image as the renderer sent it, for comparing with references.
            var png: Data?
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
            didSet {
                renderSelection()
                // Keep the sidebar's row in step, unless it's already on this story.
                if let selection, selectedNode != selection.description {
                    selectedNode = selection.description
                }
            }
        }
        /// The sidebar's selected row: a story, or a module or group. Selecting a story's row
        /// selects the story.
        var selectedNode: String? {
            didSet {
                if let selectedNode,
                    let story = stories.first(where: { $0.id.description == selectedNode })?.id,
                    selection != story
                {
                    selection = story
                }
            }
        }
        var appearance = RenderEnvironment.Appearance.light {
            didSet { renderSelection() }
        }
        private(set) var renders: [RenderKey: Rendered] = [:]
        /// Renders requested and not yet back.
        private(set) var pending: Set<RenderKey> = []

        /// What the sidebar compares against, or `nil` outside a Git repository.
        var basis: ViewerBasis? {
            didSet { if basis != oldValue { refreshHistory() } }
        }
        /// The commit the basis names, once resolved.
        private(set) var basisRevision: String?
        /// Why the basis couldn't be resolved.
        private(set) var historyError: String?
        /// Each story's change against the basis.
        private(set) var statuses: [StoryID: ChangeStatus] = [:]
        /// Filters the sidebar to stories whose ID contains it, ignoring case.
        var searchText = ""
        /// Filters the sidebar to stories that changed against the basis.
        var showsChangedOnly = false
        /// The sidebar's collapsed modules and groups, by node ID. Everything else is expanded,
        /// including groups that appear after a rebuild.
        private(set) var collapsed: Set<String> = []

        /// Left arrow in the sidebar: collapses the selected module or group, or else moves to
        /// the row's parent.
        func moveLeft() {
            guard let node = selectedNode.flatMap(findNode) else { return }
            if node.children != nil, !collapsed.contains(node.id) {
                collapsed.insert(node.id)
            } else if let parent = parent(of: node.id) {
                selectedNode = parent.id
            }
        }

        /// Right arrow in the sidebar: expands the selected module or group, or moves into it if
        /// it's already expanded.
        func moveRight() {
            guard let node = selectedNode.flatMap(findNode), let children = node.children else {
                return
            }
            if collapsed.contains(node.id) {
                collapsed.remove(node.id)
            } else if let first = children.first {
                selectedNode = first.id
            }
        }

        private func findNode(_ id: String) -> StoryNode? {
            func search(_ nodes: [StoryNode]) -> StoryNode? {
                for node in nodes {
                    if node.id == id { return node }
                    if let found = search(node.children ?? []) { return found }
                }
                return nil
            }
            return search(visibleTree)
        }

        private func parent(of id: String) -> StoryNode? {
            func search(_ nodes: [StoryNode], parent: StoryNode?) -> StoryNode? {
                for node in nodes {
                    if node.id == id { return parent }
                    if let found = search(node.children ?? [], parent: node) { return found }
                }
                return nil
            }
            return search(visibleTree, parent: nil)
        }

        func toggleExpanded(_ node: String) {
            if collapsed.remove(node) == nil { collapsed.insert(node) }
        }

        /// Whether `node` is expanded, as a binding for a disclosure group.
        func isExpanded(_ node: String) -> Binding<Bool> {
            Binding(
                get: { !self.collapsed.contains(node) },
                set: { expanded in
                    if expanded { self.collapsed.remove(node) } else { self.collapsed.insert(node) }
                })
        }

        /// The sidebar's tree, with the filters applied.
        var visibleTree: [StoryNode] {
            let query = searchText.trimmingCharacters(in: .whitespaces)
            return StoryNode.tree(
                stories.filter { story in
                    (query.isEmpty || story.id.description.localizedCaseInsensitiveContains(query))
                        && (!showsChangedOnly || (statuses[story.id] ?? .pending).isChange)
                })
        }

        private var history: (any HistorySource)?
        private let openHistory: @Sendable (URL) -> (any HistorySource)?
        private var changedPaths: [String] = []
        private var renderer: (any StoryRenderer)?
        /// Whether a change arrived during a rebuild, which then needs another.
        private var reloadAgain = false
        private var reloadTask: Task<Void, Never>?
        private let startRenderer: @Sendable (URL) async throws -> any StoryRenderer

        init(
            package: URL,
            startRenderer: @escaping @Sendable (URL) async throws -> any StoryRenderer = {
                try await RendererSupervisor.start(for: $0)
            },
            openHistory: @escaping @Sendable (URL) -> (any HistorySource)? = {
                try? History(package: $0)
            }
        ) {
            self.package = package
            self.startRenderer = startRenderer
            self.openHistory = openHistory
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
                let package = package
                let openHistory = openHistory
                if let history = await Task.detached(operation: { openHistory(package) }).value {
                    self.history = history
                    basis = await Task.detached { history.defaultBasis() }.value
                }
            } catch {
                status = .failed(String(describing: error))
            }
        }

        /// Responds to edits: rebuilds once the changes have paused for `debounce`. Changes during
        /// a rebuild cause exactly one more, after it.
        func filesChanged(_ paths: [String], debounce: Duration = .milliseconds(300)) {
            guard status == .ready else { return }
            log(
                "changed: \(paths.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", "))"
            )
            if isRebuilding {
                reloadAgain = true
                return
            }
            reloadTask?.cancel()
            reloadTask = Task {
                try? await Task.sleep(for: debounce)
                guard !Task.isCancelled else { return }
                await reload()
            }
        }

        /// Builds the package again and shows the new build's stories. Until then, and if the
        /// build fails, the current renders stay up.
        func reload() async {
            guard let renderer, !isRebuilding else {
                if isRebuilding { reloadAgain = true }
                return
            }
            defer {
                if reloadAgain {
                    reloadAgain = false
                    Task { await reload() }
                }
            }
            isRebuilding = true
            defer { isRebuilding = false }
            log("rebuilding")
            do {
                generation = try await renderer.rebuild()
                skippedAhead = []
                try await listStories()
                // Edits change what differs from the basis.
                refreshHistory()
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

        /// Whether stories render ahead of the selection, so switching to them is instant.
        var rendersAhead = true
        /// The render in progress. One at a time: the renderer answers in order anyway, so a
        /// new selection waits at most for the render ahead of it, which has a short timeout.
        private var inFlight: RenderKey?
        /// Background renders that failed this generation. They render again only when
        /// selected, with the full timeout.
        private var skippedAhead: Set<RenderKey> = []

        private func renderSelection() {
            renderNext()
        }

        /// Whether `key` has no render from the current generation.
        private func needsRender(_ key: RenderKey) -> Bool {
            (renders[key]?.generation ?? 0) < generation
        }

        /// The next render to do: the selection, then the other stories in the sidebar's order
        /// from just after it, in the same appearance.
        private func nextKey() -> RenderKey? {
            if let key = currentKey, needsRender(key) { return key }
            guard rendersAhead, !stories.isEmpty else { return nil }
            let ids = stories.map(\.id)
            let start = selection.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            for offset in 0..<ids.count {
                let key = RenderKey(
                    story: ids[(start + offset) % ids.count], appearance: appearance)
                if needsRender(key), !skippedAhead.contains(key) { return key }
            }
            return nil
        }

        private func renderNext() {
            guard inFlight == nil, let renderer, let key = nextKey() else { return }
            inFlight = key
            let background = key != currentKey
            pending.insert(key)
            var environment = RenderEnvironment()
            environment.appearance = key.appearance
            let generation = generation
            Task {
                defer {
                    pending.remove(key)
                    inFlight = nil
                    renderNext()
                }
                let render: Render
                var png: Data?
                do {
                    png = try await renderer.render(
                        key.story, in: environment, background: background)
                    if let png, let image = NSImage(data: png) {
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
                    // A background render that fails may only have been slow; try it properly
                    // if someone selects it.
                    if background {
                        skippedAhead.insert(key)
                        return
                    }
                    render = .failed(String(describing: error))
                }
                // Keep a newer render if one already arrived.
                if (renders[key]?.generation ?? 0) <= generation {
                    renders[key] = Rendered(render: render, generation: generation, png: png)
                    if generation == self.generation, key.appearance == appearance {
                        compareWithBasis(key)
                    }
                }
            }
        }

        // MARK: History

        /// Resolves the basis and marks stories whose source changed, then compares every
        /// current render with its reference at the basis.
        private func refreshHistory() {
            guard let history, let basis else { return }
            Task {
                let result = await Task.detached {
                    Result { try history.changes(against: basis) }
                }.value
                // A newer basis may have been chosen meanwhile.
                guard basis == self.basis else { return }
                switch result {
                case .success(let changes):
                    basisRevision = changes.revision
                    changedPaths = changes.paths
                    historyError = nil
                case .failure(let error):
                    basisRevision = nil
                    changedPaths = []
                    historyError = String(describing: error)
                    statuses = [:]
                    return
                }
                statuses = Dictionary(
                    uniqueKeysWithValues: stories.map { story in
                        (
                            story.id,
                            History.sourceChanged(story, in: changedPaths)
                                ? ChangeStatus.sourceChanged : .pending
                        )
                    })
                for key in renders.keys where key.appearance == appearance {
                    compareWithBasis(key)
                }
            }
        }

        /// Compares the current generation's render for `key` with the basis's reference, and
        /// records the story's status.
        private func compareWithBasis(_ key: RenderKey) {
            guard let history, let revision = basisRevision,
                let rendered = renders[key], rendered.generation == generation
            else { return }
            guard case .image = rendered.render, let png = rendered.png else {
                statuses[key.story] = .failed
                return
            }
            Task {
                let status = await Task.detached {
                    History.imageStatus(
                        render: png,
                        reference: try? history.reference(
                            for: key.story, appearance: key.appearance, at: revision))
                }.value
                // Only if nothing has moved on meanwhile.
                guard revision == basisRevision, renders[key] == rendered else { return }
                statuses[key.story] = status
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
            var basis: String?
            /// How many stories have each change status.
            var changes: [String: Int]
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
                buildError: buildError, basis: basis?.title,
                changes: Dictionary(grouping: statuses.values, by: { "\($0)" }).mapValues(\.count))
        }

        /// Writes a line to standard error, which `swiftbook view` sends to the viewer's log.
        private func log(_ message: String) {
            FileHandle.standardError.write(Data("swiftbook-viewer: \(message)\n".utf8))
        }
    }
#endif
