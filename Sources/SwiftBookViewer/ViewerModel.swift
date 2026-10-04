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

        /// A value for each dimension the viewer varies.
        struct Variant: Hashable {
            var appearance = RenderEnvironment.Appearance.light
            var layoutDirection = LayoutDirection.leftToRight
        }

        struct RenderKey: Hashable {
            let story: StoryID
            let variant: Variant
        }

        /// (A) How the canvas lays out the selection.
        enum CompareMode: String, CaseIterable, Hashable {
            case single
            /// Two values of the comparison dimension, side by side.
            case twoUp
            /// Every value of the comparison dimension across, plus the difference when comparing
            /// revisions, and every value of a second dimension down: color scheme, or layout
            /// direction when comparing color schemes.
            case grid
        }

        /// (B) The dimension a comparison spreads across.
        enum CompareDimension: String, CaseIterable, Hashable {
            case appearance
            case layoutDirection
            /// The reference at the basis against the working tree's render.
            case revision
        }

        /// One image on the canvas.
        struct Cell: Identifiable, Hashable {
            enum Content: Hashable {
                case render(RenderKey)
                /// The Mac reference for the key at the basis.
                case reference(RenderKey)
                /// Where the key's render differs from its reference at the basis.
                case diff(RenderKey)
            }

            let title: String
            let content: Content
            var id: Content { content }
        }

        /// What a cell shows.
        enum CellState: Equatable {
            case image(NSImage)
            case failed(String)
            /// Waiting on a render, a reference, or a comparison.
            case loading
            /// Nothing to show, and why.
            case empty(String)
        }

        /// How a render differs from its reference at the basis.
        struct Comparison: Equatable {
            let changedPixelRatio: Double
            let maxDeltaE: Double
            let sizesMatch: Bool
            let matches: Bool
            /// The changed pixels, highlighted over the render.
            let image: NSImage?
        }

        private struct ReferenceKey: Hashable {
            let story: StoryID
            let appearance: RenderEnvironment.Appearance
            let revision: String
        }

        private enum Reference: Equatable {
            case found(Data)
            case missing
            case failed(String)
        }

        private struct ComparisonKey: Hashable {
            let render: RenderKey
            let revision: String
            let generation: Int
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
                visibleCellsChanged()
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
        /// (C) The color scheme, for every cell not spread across it.
        var appearance = RenderEnvironment.Appearance.light {
            didSet { visibleCellsChanged() }
        }
        /// (C) The layout direction, for every cell not spread across it.
        var layoutDirection = LayoutDirection.leftToRight {
            didSet { visibleCellsChanged() }
        }
        var compareMode = CompareMode.single {
            didSet { visibleCellsChanged() }
        }
        var compareDimension = CompareDimension.appearance {
            didSet { visibleCellsChanged() }
        }
        /// The canvas's magnification, shared by every cell.
        var zoom = 1.0
        /// The canvas's scroll offset, shared by every cell so they show the same region.
        var panOffset = CGPoint.zero
        /// The variant the pickers choose.
        var variant: Variant { Variant(appearance: appearance, layoutDirection: layoutDirection) }
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

        /// A row of the sidebar: a node, indented by its depth in the tree.
        struct SidebarRow: Identifiable, Hashable {
            let node: StoryNode
            let depth: Int
            var id: String { node.id }
        }

        /// The sidebar's rows: the filtered tree, flattened, without the children of collapsed
        /// modules and groups. A flat list keeps the sidebar's rows in step with the tree; nested
        /// disclosure groups in a selectable list left stale rows behind when the filters
        /// changed.
        var sidebarRows: [SidebarRow] {
            var rows: [SidebarRow] = []
            func add(_ nodes: [StoryNode], depth: Int) {
                for node in nodes {
                    rows.append(SidebarRow(node: node, depth: depth))
                    if let children = node.children, !collapsed.contains(node.id) {
                        add(children, depth: depth + 1)
                    }
                }
            }
            add(visibleTree, depth: 0)
            return rows
        }

        func isExpanded(_ node: String) -> Bool { !collapsed.contains(node) }

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
                    visibleCellsChanged()
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
            selection.map { RenderKey(story: $0, variant: variant) }
        }

        /// The render the canvas shows: the selection in the chosen appearance, possibly from an
        /// earlier generation while the current one renders.
        var currentRender: Render? {
            currentKey.flatMap { renders[$0]?.render }
        }

        /// Whether the canvas is waiting on a render of the selection.
        var isRenderingSelection: Bool {
            !pending.isDisjoint(with: visibleRenderKeys)
        }

        /// Whether stories render ahead of the selection, so switching to them is instant.
        var rendersAhead = true
        /// The render in progress. One at a time: the renderer answers in order anyway, so a
        /// new selection waits at most for the render ahead of it, which has a short timeout.
        private var inFlight: RenderKey?
        /// Background renders that failed this generation. They render again only when
        /// selected, with the full timeout.
        private var skippedAhead: Set<RenderKey> = []

        /// Starts whatever the canvas's cells need: renders, references, and comparisons.
        private func visibleCellsChanged() {
            renderNext()
            loadReferences()
            compareVisible()
        }

        /// The renders the canvas's cells need, in cell order.
        private var visibleRenderKeys: [RenderKey] {
            cells.compactMap { cell in
                switch cell.content {
                case .render(let key), .diff(let key): key
                case .reference: nil
                }
            }
        }

        /// Whether `key` has no render from the current generation.
        private func needsRender(_ key: RenderKey) -> Bool {
            (renders[key]?.generation ?? 0) < generation
        }

        /// The next render to do: the canvas's cells, then the other stories in the sidebar's
        /// order from just after the selection, in the pickers' variant.
        private func nextKey() -> RenderKey? {
            if let key = visibleRenderKeys.first(where: needsRender) { return key }
            guard rendersAhead, !stories.isEmpty else { return nil }
            let ids = stories.map(\.id)
            let start = selection.flatMap { ids.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            for offset in 0..<ids.count {
                let key = RenderKey(story: ids[(start + offset) % ids.count], variant: variant)
                if needsRender(key), !skippedAhead.contains(key) { return key }
            }
            return nil
        }

        private func renderNext() {
            guard inFlight == nil, let renderer, let key = nextKey() else { return }
            inFlight = key
            let background = !visibleRenderKeys.contains(key)
            pending.insert(key)
            var environment = RenderEnvironment()
            environment.appearance = key.variant.appearance
            environment.layoutDirection = key.variant.layoutDirection
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
                    if let png, let image = Self.image(png, scale: environment.scale) {
                        render = .image(image)
                        log("rendered \(key.story) (\(key.variant.appearance))")
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
                    if generation == self.generation, setsStatus(key) {
                        compareWithBasis(key)
                    }
                    compareVisible()
                }
            }
        }

        /// `png` as an image of its size in points, given the scale it was rendered at.
        nonisolated static func image(_ png: Data, scale: Double) -> NSImage? {
            guard let image = NSImage(data: png) else { return nil }
            if let representation = image.representations.first {
                image.size = CGSize(
                    width: Double(representation.pixelsWide) / scale,
                    height: Double(representation.pixelsHigh) / scale)
            }
            return image
        }

        // MARK: Canvas

        /// The canvas's cells, per the toolbar.
        var cells: [Cell] { cellRows.flatMap { $0 } }

        /// The canvas's cells by row. Single and 2-up have one row; the grid has a row for each
        /// value of its second dimension.
        var cellRows: [[Cell]] {
            guard let selection else { return [] }
            guard compareMode != .single else {
                return [
                    [
                        Cell(
                            title: "",
                            content: .render(RenderKey(story: selection, variant: variant)))
                    ]
                ]
            }
            typealias Value = (title: String, change: (inout Variant) -> Void)
            let appearances: [Value] = [
                ("Light", { $0.appearance = .light }), ("Dark", { $0.appearance = .dark }),
            ]
            let directions: [Value] = [
                ("Left to right", { $0.layoutDirection = .leftToRight }),
                ("Right to left", { $0.layoutDirection = .rightToLeft }),
            ]
            let rows: [Value] =
                compareMode != .grid
                ? [("", { _ in })] : compareDimension == .appearance ? directions : appearances
            let basisTitle = [basis?.title ?? "Basis", basisRevision.map { String($0.prefix(7)) }]
                .compactMap { $0 }.joined(separator: " · ")
            return rows.map { row in
                var rowVariant = variant
                row.change(&rowVariant)
                let key = RenderKey(story: selection, variant: rowVariant)
                func title(_ column: String) -> String {
                    [row.title, column].filter { !$0.isEmpty }.joined(separator: " · ")
                }
                func cell(_ column: Value) -> Cell {
                    var variant = rowVariant
                    column.change(&variant)
                    return Cell(
                        title: title(column.title),
                        content: .render(RenderKey(story: selection, variant: variant)))
                }
                switch compareDimension {
                case .appearance: return appearances.map(cell)
                case .layoutDirection: return directions.map(cell)
                case .revision:
                    let cells = [
                        Cell(title: title(basisTitle), content: .reference(key)),
                        Cell(title: title("Working tree"), content: .render(key)),
                    ]
                    return compareMode == .grid
                        ? cells + [Cell(title: title("Difference"), content: .diff(key))] : cells
                }
            }
        }

        func state(of cell: Cell) -> CellState {
            switch cell.content {
            case .render(let key):
                switch renders[key]?.render {
                case .image(let image)?: return .image(image)
                case .failed(let message)?: return .failed(message)
                case nil: return .loading
                }
            case .reference(let key):
                if let unavailable = referenceUnavailable(key) { return .empty(unavailable) }
                switch references[referenceKey(key)!] {
                case .found(let png)?:
                    return Self.image(png, scale: RenderEnvironment().scale).map(CellState.image)
                        ?? .failed("the reference isn't a readable image")
                case .missing?: return .empty("No reference at the basis")
                case .failed(let message)?: return .failed(message)
                case nil: return .loading
                }
            case .diff(let key):
                if let unavailable = referenceUnavailable(key) { return .empty(unavailable) }
                if case .missing? = references[referenceKey(key)!] {
                    return .empty("No reference at the basis")
                }
                if case .failed(let message)? = renders[key]?.render { return .failed(message) }
                guard let comparison = comparison(for: key) else { return .loading }
                return comparison.image.map(CellState.image) ?? .empty("Identical")
            }
        }

        /// How the cell's render differs from its reference at the basis, when comparing
        /// revisions.
        func comparison(of cell: Cell) -> Comparison? {
            switch cell.content {
            case .render(let key), .diff(let key):
                compareDimension == .revision && compareMode != .single ? comparison(for: key) : nil
            case .reference: nil
            }
        }

        private func comparison(for key: RenderKey) -> Comparison? {
            guard let revision = basisRevision else { return nil }
            return comparisons[
                ComparisonKey(render: key, revision: revision, generation: generation)]
        }

        private var references: [ReferenceKey: Reference] = [:]
        private var loadingReferences: Set<ReferenceKey> = []
        private var comparisons: [ComparisonKey: Comparison] = [:]
        private var comparing: Set<ComparisonKey> = []

        private func referenceKey(_ key: RenderKey) -> ReferenceKey? {
            basisRevision.map {
                ReferenceKey(story: key.story, appearance: key.variant.appearance, revision: $0)
            }
        }

        /// Why `key` can't have a reference, if it can't.
        private func referenceUnavailable(_ key: RenderKey) -> String? {
            if history == nil { return "Not in a Git repository" }
            if let historyError { return historyError }
            if key.variant.layoutDirection != .leftToRight {
                return "References are recorded left to right only"
            }
            return basisRevision == nil ? "Resolving the basis…" : nil
        }

        /// Fetches the references the canvas's cells need from the basis.
        private func loadReferences() {
            guard let history, compareDimension == .revision, compareMode != .single else { return }
            for key in visibleRenderKeys where referenceUnavailable(key) == nil {
                guard let referenceKey = referenceKey(key), references[referenceKey] == nil,
                    !loadingReferences.contains(referenceKey)
                else { continue }
                loadingReferences.insert(referenceKey)
                Task {
                    let reference = await Task.detached { () -> Reference in
                        do {
                            return try history.reference(
                                for: referenceKey.story, appearance: referenceKey.appearance,
                                at: referenceKey.revision
                            ).map(Reference.found) ?? .missing
                        } catch {
                            return .failed(String(describing: error))
                        }
                    }.value
                    loadingReferences.remove(referenceKey)
                    references[referenceKey] = reference
                    compareVisible()
                }
            }
        }

        /// Compares the canvas's renders with their references, once both are in.
        private func compareVisible() {
            guard compareDimension == .revision, compareMode != .single else { return }
            for key in visibleRenderKeys {
                guard let referenceKey = referenceKey(key),
                    case .found(let reference)? = references[referenceKey],
                    let rendered = renders[key], rendered.generation == generation,
                    let png = rendered.png
                else { continue }
                let comparisonKey = ComparisonKey(
                    render: key, revision: referenceKey.revision, generation: generation)
                guard comparisons[comparisonKey] == nil, !comparing.contains(comparisonKey) else {
                    continue
                }
                comparing.insert(comparisonKey)
                let scale = RenderEnvironment().scale
                Task {
                    let comparison = await Task.detached { () -> Comparison? in
                        guard let expected = try? SnapshotStore.image(reference, at: "reference"),
                            let actual = try? SnapshotStore.image(png, at: "render"),
                            let diff = try? ImageDiff.compare(expected: expected, actual: actual)
                        else { return nil }
                        let image =
                            diff.matches
                            ? nil
                            : try? diff.pngData().flatMap {
                                Self.image($0, scale: scale)
                            }
                        return Comparison(
                            changedPixelRatio: diff.changedPixelRatio, maxDeltaE: diff.maxDeltaE,
                            sizesMatch: diff.sizesMatch, matches: diff.matches, image: image)
                    }.value
                    comparing.remove(comparisonKey)
                    if let comparison { comparisons[comparisonKey] = comparison }
                }
            }
        }

        private static let zoomLevels = [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8]

        func zoomIn() {
            zoom = Self.zoomLevels.first { $0 > zoom + 0.001 } ?? Self.zoomLevels.last!
        }

        func zoomOut() {
            zoom = Self.zoomLevels.last { $0 < zoom - 0.001 } ?? Self.zoomLevels.first!
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
                for key in renders.keys where setsStatus(key) {
                    compareWithBasis(key)
                }
                loadReferences()
                compareVisible()
            }
        }

        /// Whether `key`'s render decides its story's status: it's in the chosen appearance, and
        /// left to right like the references.
        private func setsStatus(_ key: RenderKey) -> Bool {
            key.variant == Variant(appearance: appearance)
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
                            for: key.story, appearance: key.variant.appearance, at: revision))
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
            /// The canvas's cells, by title.
            var cells: [String]
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
                changes: Dictionary(grouping: statuses.values, by: { "\($0)" }).mapValues(\.count),
                cells: cells.map(\.title))
        }

        /// Writes a line to standard error, which `swiftbook view` sends to the viewer's log.
        private func log(_ message: String) {
            FileHandle.standardError.write(Data("swiftbook-viewer: \(message)\n".utf8))
        }
    }
#endif
