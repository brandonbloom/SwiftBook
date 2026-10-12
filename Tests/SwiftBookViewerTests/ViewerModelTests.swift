#if os(macOS)
    import AppKit
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookViewer

    /// A renderer that lists fixed stories and renders a solid image, recording what it's asked.
    final class FakeRenderer: StoryRenderer, @unchecked Sendable {
        // Unchecked: `lock` guards the mutable state.
        private let lock = NSLock()
        private var _stories: [StoryInfo]
        private var _generation = 1
        private var _failNextBuild: String?
        private var _requests: [String] = []
        private var _builds = 0
        let failing: Set<String>
        /// How long each rebuild takes.
        let buildTime: Duration

        init(_ ids: [String], failing: Set<String> = [], buildTime: Duration = .zero) {
            _stories = Self.infos(ids)
            self.failing = failing
            self.buildTime = buildTime
        }

        /// How many rebuilds have started.
        var builds: Int { lock.withLock { _builds } }

        static func infos(_ ids: [String]) -> [StoryInfo] {
            ids.map {
                let parts = $0.split(separator: "/").map(String.init)
                return StoryInfo(
                    id: StoryID(module: parts[0], group: parts[1], name: parts[2]),
                    fileID: "\(parts[0])/\(parts[1]).swift")
            }
        }

        /// Every render request, as "<story> <appearance> g<generation>", with " rtl" for right
        /// to left and " ahead" for a background render.
        var requests: [String] { lock.withLock { _requests } }

        /// Replaces the stories the next build will list.
        func setStories(_ ids: [String]) { lock.withLock { _stories = Self.infos(ids) } }

        /// Makes the next rebuild fail with `message`.
        func failNextBuild(_ message: String) { lock.withLock { _failNextBuild = message } }

        func generation() async -> Int { lock.withLock { _generation } }

        func stories() async throws -> [StoryInfo] { lock.withLock { _stories } }

        /// Every story opened interactively, as "<story> <appearance>", with " rtl" for right to
        /// left.
        var opened: [String] { lock.withLock { _opened } }
        private var _opened: [String] = []

        func open(_ story: StoryID, in environment: RenderEnvironment) async throws {
            lock.withLock {
                _opened.append(
                    "\(story) \(environment.appearance)"
                        + (environment.layoutDirection == .rightToLeft ? " rtl" : ""))
            }
            if failing.contains(story.description) {
                throw RendererError(description: "boom")
            }
        }

        func rebuild() async throws -> Int {
            lock.withLock { _builds += 1 }
            try await Task.sleep(for: buildTime)
            return try lock.withLock {
                if let message = _failNextBuild {
                    _failNextBuild = nil
                    throw RendererError(description: message)
                }
                _generation += 1
                return _generation
            }
        }

        func render(_ story: StoryID, in environment: RenderEnvironment, background: Bool)
            async throws -> Data
        {
            lock.withLock {
                _requests.append(
                    "\(story) \(environment.appearance) g\(_generation)"
                        + (environment.layoutDirection == .rightToLeft ? " rtl" : "")
                        + (background ? " ahead" : "")
                )
            }
            if failing.contains(story.description) {
                throw RendererError(description: "boom")
            }
            return Self.png
        }

        /// What every render looks like: solid blue.
        static let png: Data = {
            let image = NSImage(size: CGSize(width: 40, height: 20), flipped: false) { rect in
                NSColor.systemBlue.setFill()
                rect.fill()
                return true
            }
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            return bitmap.representation(using: .png, properties: [:])!
        }()
    }

    @MainActor @Suite struct ViewerModelTests {
        /// A model of `renderer`'s stories. Rendering ahead is off unless asked for, so tests can
        /// check exactly what renders.
        func model(_ renderer: FakeRenderer, rendersAhead: Bool = false) -> ViewerModel {
            let model = ViewerModel(package: URL(filePath: "/tmp/Package")) { _ in renderer }
            model.rendersAhead = rendersAhead
            return model
        }

        /// Waits until no render is in progress.
        func settle(_ model: ViewerModel) async {
            for _ in 0..<200 {
                guard !model.pending.isEmpty else { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        static func story(_ id: String) -> StoryID {
            FakeRenderer.infos([id])[0].id
        }

        @Test func groupsStoriesByModuleAndFile() {
            let tree = StoryNode.tree(
                FakeRenderer.infos(["M/A/One", "M/B/Two", "M/A/Three", "N/C/Four"]))
            #expect(tree.map(\.id) == ["M", "N"])
            #expect(tree[0].children?.map(\.title) == ["A", "B"])
            #expect(tree[0].children?[0].children?.map(\.title) == ["One", "Three"])
            #expect(tree[0].children?[0].children?[0].story?.description == "M/A/One")
        }

        @Test func startsAndRendersTheFirstStory() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Two"])
            let model = model(renderer)
            await model.start()
            #expect(model.status == .ready)
            #expect(model.generation == 1)
            #expect(model.selection?.description == "M/A/One")
            await settle(model)
            #expect(model.summary.render == "image 20×10")
            #expect(renderer.requests == ["M/A/One light g1"])
        }

        @Test func rendersEachSelectionAndAppearanceOncePerGeneration() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Two"])
            let model = model(renderer)
            await model.start()
            await settle(model)
            model.appearance = .dark
            await settle(model)
            model.selection = Self.story("M/A/Two")
            await settle(model)
            model.appearance = .light
            model.selection = Self.story("M/A/One")
            await settle(model)
            #expect(
                renderer.requests == [
                    "M/A/One light g1", "M/A/One dark g1", "M/A/Two dark g1", "M/A/Two light g1",
                ])
        }

        @Test func showsRenderFailures() async {
            let model = model(FakeRenderer(["M/A/One"], failing: ["M/A/One"]))
            await model.start()
            await settle(model)
            #expect(model.summary.render == "failed: boom")
        }

        @Test func reloadsWithTheNewBuildsStories() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Two"])
            let model = model(renderer)
            await model.start()
            await settle(model)
            renderer.setStories(["M/A/Two", "M/A/Three"])
            await model.reload()
            // The selection is gone from the new build, so the first story takes its place.
            #expect(model.generation == 2)
            #expect(model.selection?.description == "M/A/Two")
            #expect(model.tree[0].children?[0].children?.map(\.title) == ["Two", "Three"])
            await settle(model)
            #expect(renderer.requests == ["M/A/One light g1", "M/A/Two light g2"])
        }

        @Test func rerendersTheSelectionAfterAReloadWithoutBlanking() async {
            let renderer = FakeRenderer(["M/A/One"])
            let model = model(renderer)
            await model.start()
            await settle(model)
            await model.reload()
            // The old render stays up while the new generation's renders.
            #expect(model.summary.render == "image 20×10")
            await settle(model)
            #expect(model.renders.values.first?.generation == 2)
            #expect(renderer.requests == ["M/A/One light g1", "M/A/One light g2"])
        }

        @Test func keepsTheLastGoodRendersWhenABuildFails() async {
            let renderer = FakeRenderer(["M/A/One"])
            let model = model(renderer)
            await model.start()
            await settle(model)
            renderer.failNextBuild("error: expected '}'")
            await model.reload()
            #expect(model.buildError == "error: expected '}'")
            #expect(model.generation == 1)
            #expect(model.summary.render == "image 20×10")
            await model.reload()
            #expect(model.buildError == nil)
            #expect(model.generation == 2)
        }

        @Test func rebuildsOnceForABurstOfEdits() async throws {
            let renderer = FakeRenderer(["M/A/One"])
            let model = model(renderer)
            await model.start()
            for _ in 0..<5 {
                model.filesChanged(["/tmp/Package/Sources/A.swift"], debounce: .milliseconds(50))
            }
            try await Task.sleep(for: .milliseconds(300))
            #expect(renderer.builds == 1)
            #expect(model.generation == 2)
        }

        @Test func rebuildsOnceMoreForEditsDuringABuild() async throws {
            let renderer = FakeRenderer(["M/A/One"], buildTime: .milliseconds(300))
            let model = model(renderer)
            await model.start()
            model.filesChanged(["/tmp/Package/Sources/A.swift"], debounce: .milliseconds(10))
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.isRebuilding)
            // Several edits mid-build make one more build, not several.
            for _ in 0..<3 {
                model.filesChanged(["/tmp/Package/Sources/B.swift"], debounce: .milliseconds(10))
            }
            try await Task.sleep(for: .milliseconds(900))
            #expect(renderer.builds == 2)
            #expect(model.generation == 3)
            #expect(!model.isRebuilding)
        }

        @Test func rendersAheadOfTheSelectionInSidebarOrder() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Two", "M/B/Three", "M/B/Four"])
            let model = model(renderer, rendersAhead: true)
            await model.start()
            model.selection = Self.story("M/A/Two")
            await settle(model)
            // The first story was selected at start; then the selection, then the rest after it.
            // Two may already be rendering ahead when it's selected, if One finished first.
            #expect(
                renderer.requests.map {
                    $0 == "M/A/Two light g1 ahead" ? "M/A/Two light g1" : $0
                } == [
                    "M/A/One light g1", "M/A/Two light g1", "M/B/Three light g1 ahead",
                    "M/B/Four light g1 ahead",
                ])
            // Everything is cached, so switching renders nothing.
            model.selection = Self.story("M/B/Four")
            await settle(model)
            #expect(renderer.requests.count == 4)
            #expect(model.summary.render == "image 20×10")
        }

        @Test func rendersAheadAgainAfterAReload() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Two"])
            let model = model(renderer, rendersAhead: true)
            await model.start()
            await settle(model)
            await model.reload()
            await settle(model)
            #expect(
                renderer.requests == [
                    "M/A/One light g1", "M/A/Two light g1 ahead", "M/A/One light g2",
                    "M/A/Two light g2 ahead",
                ])
        }

        @Test func rendersFailedBackgroundRendersOnlyWhenSelected() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Slow"], failing: ["M/A/Slow"])
            let model = model(renderer, rendersAhead: true)
            await model.start()
            await settle(model)
            // A background failure isn't shown or retried in the background.
            #expect(model.renders[.init(story: Self.story("M/A/Slow"), variant: .init())] == nil)
            model.selection = Self.story("M/A/Slow")
            await settle(model)
            #expect(
                renderer.requests == [
                    "M/A/One light g1", "M/A/Slow light g1 ahead", "M/A/Slow light g1",
                ])
            #expect(model.summary.render == "failed: boom")
        }

        @Test func togglesGroupsOpenAndClosed() async {
            let model = model(FakeRenderer(["M/A/One", "M/B/Two"]))
            await model.start()
            #expect(model.sidebarRows.map(\.id) == ["M", "M/A", "M/A/One", "M/B", "M/B/Two"])
            #expect(model.sidebarRows.map(\.depth) == [0, 1, 2, 1, 2])
            model.toggleExpanded("M/A")
            #expect(!model.isExpanded("M/A"))
            #expect(model.sidebarRows.map(\.id) == ["M", "M/A", "M/B", "M/B/Two"])
            model.toggleExpanded("M")
            #expect(model.sidebarRows.map(\.id) == ["M"])
            model.toggleExpanded("M")
            model.toggleExpanded("M/A")
            #expect(model.collapsed.isEmpty)
            // Filtering removes rows rather than leaving them behind.
            model.searchText = "two"
            #expect(model.sidebarRows.map(\.id) == ["M", "M/B", "M/B/Two"])
        }

        @Test func arrowKeysCollapseExpandAndMoveThroughTheOutline() async {
            let model = model(FakeRenderer(["M/A/One", "M/A/Two"]))
            await model.start()
            model.selection = Self.story("M/A/Two")
            #expect(model.selectedNode == "M/A/Two")
            model.moveLeft()
            #expect(model.selectedNode == "M/A")
            #expect(model.selection == Self.story("M/A/Two"))
            model.moveLeft()
            #expect(model.collapsed == ["M/A"])
            model.moveLeft()
            #expect(model.selectedNode == "M")
            model.moveRight()
            #expect(model.selectedNode == "M/A")
            model.moveRight()
            #expect(model.collapsed.isEmpty)
            model.moveRight()
            #expect(model.selectedNode == "M/A/One")
            #expect(model.selection == Self.story("M/A/One"))
            // A story has nothing to expand.
            model.moveRight()
            #expect(model.selectedNode == "M/A/One")
        }

        @Test func comparesAcrossTheChosenDimension() async {
            let renderer = FakeRenderer(["M/A/One"])
            let model = model(renderer)
            await model.start()
            await settle(model)
            #expect(model.cells.map(\.title) == [""])

            model.compareMode = .twoUp
            #expect(model.cells.map(\.title) == ["Light", "Dark"])
            await settle(model)
            #expect(renderer.requests == ["M/A/One light g1", "M/A/One dark g1"])
            #expect(model.cells.allSatisfy { model.state(of: $0) != .loading })

            // The other pickers apply to every cell.
            model.appearance = .dark
            model.compareDimension = .layoutDirection
            #expect(model.cells.map(\.title) == ["Left to right", "Right to left"])
            await settle(model)
            #expect(renderer.requests.last == "M/A/One dark g1 rtl")
            // The grid adds color scheme down.
            model.compareMode = .grid
            #expect(
                model.cellRows.map { $0.map(\.title) } == [
                    ["Light · Left to right", "Light · Right to left"],
                    ["Dark · Left to right", "Dark · Right to left"],
                ])
            // Comparing color schemes, it adds layout direction down.
            model.compareDimension = .appearance
            #expect(
                model.cellRows.map { $0.map(\.title) } == [
                    ["Left to right · Light", "Left to right · Dark"],
                    ["Right to left · Light", "Right to left · Dark"],
                ])
            await settle(model)
            #expect(Set(renderer.requests).count == 4)
        }

        @Test func opensStoriesInteractively() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Bad"], failing: ["M/A/Bad"])
            let model = model(renderer)
            await model.start()
            model.appearance = .dark
            model.openInteractively()
            model.compareMode = .twoUp
            model.compareDimension = .layoutDirection
            model.openInteractively(model.cells[1].variant)
            for _ in 0..<100 where renderer.opened.count < 2 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(renderer.opened == ["M/A/One dark", "M/A/One dark rtl"])

            model.selection = Self.story("M/A/Bad")
            model.openInteractively()
            for _ in 0..<100 where model.openError == nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.openError == "boom")
        }

        @Test func zoomsInSteps() {
            let model = model(FakeRenderer([]))
            model.zoomIn()
            #expect(model.zoom == 1.5)
            model.zoom = 1.2
            model.zoomOut()
            #expect(model.zoom == 1)
            for _ in 0..<20 { model.zoomOut() }
            #expect(model.zoom == 0.25)
        }

        @Test func reportsARendererThatWontStart() async {
            let model = ViewerModel(package: URL(filePath: "/tmp/Package")) { _ in
                throw RendererError(description: "no library products")
            }
            await model.start()
            #expect(model.status == .failed("no library products"))
            #expect(model.tree.isEmpty)
        }
    }
#endif
