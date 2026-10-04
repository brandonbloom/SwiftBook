#if os(macOS)
    import AppKit
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookViewer

    /// A renderer that lists fixed stories and renders a solid image, recording what it's asked.
    final class FakeRenderer: StoryRenderer, @unchecked Sendable {
        let stories: [StoryInfo]
        let failing: Set<String>
        private let lock = NSLock()
        private var _requests: [String] = []
        var requests: [String] { lock.withLock { _requests } }

        init(_ ids: [String], failing: Set<String> = []) {
            stories = ids.map {
                let parts = $0.split(separator: "/").map(String.init)
                return StoryInfo(id: StoryID(module: parts[0], group: parts[1], name: parts[2]))
            }
            self.failing = failing
        }

        func stories() async throws -> [StoryInfo] { stories }

        func render(_ story: StoryID, in environment: RenderEnvironment) async throws -> Data {
            lock.withLock { _requests.append("\(story) \(environment.appearance)") }
            if failing.contains(story.description) {
                throw RendererError(description: "boom")
            }
            let image = NSImage(size: CGSize(width: 40, height: 20), flipped: false) { rect in
                NSColor.systemBlue.setFill()
                rect.fill()
                return true
            }
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            return bitmap.representation(using: .png, properties: [:])!
        }

        func shutdown() async {}
    }

    @MainActor @Suite struct ViewerModelTests {
        func model(_ renderer: FakeRenderer) -> ViewerModel {
            ViewerModel(package: URL(filePath: "/tmp/Package")) { _ in renderer }
        }

        /// Waits until no render is in progress.
        func settle(_ model: ViewerModel) async {
            for _ in 0..<200 {
                guard model.renders.values.contains(.rendering) else { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }

        @Test func groupsStoriesByModuleAndFile() {
            let tree = StoryNode.tree(
                FakeRenderer(["M/A/One", "M/B/Two", "M/A/Three", "N/C/Four"]).stories)
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
            #expect(model.selection?.description == "M/A/One")
            await settle(model)
            #expect(model.summary.render == "image 20×10")
            #expect(renderer.requests == ["M/A/One light"])
        }

        @Test func rendersEachSelectionAndAppearanceOnce() async {
            let renderer = FakeRenderer(["M/A/One", "M/A/Two"])
            let model = model(renderer)
            await model.start()
            await settle(model)
            model.appearance = .dark
            await settle(model)
            model.selection = StoryID(module: "M", group: "A", name: "Two")
            await settle(model)
            model.appearance = .light
            model.selection = StoryID(module: "M", group: "A", name: "One")
            await settle(model)
            #expect(
                renderer.requests == [
                    "M/A/One light", "M/A/One dark", "M/A/Two dark", "M/A/Two light",
                ])
        }

        @Test func showsRenderFailures() async {
            let model = model(FakeRenderer(["M/A/One"], failing: ["M/A/One"]))
            await model.start()
            await settle(model)
            #expect(model.summary.render == "failed: boom")
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
