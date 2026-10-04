#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookViewer

    /// An edit reaching the canvas, through a real file watcher, build, and renderer.
    @MainActor @Suite(.serialized) struct LiveReloadTests {
        @Test func anEditRerendersTheSelection() async throws {
            let package = RendererSupervisorTests.faultZoo
            let model = ViewerModel(package: package)
            await model.start()
            #expect(model.status == .ready)
            model.selection = StoryID(module: "FaultZoo", group: "Faults", name: "Fine")
            let watcher = FileWatcher(directory: package) { paths in
                Task { @MainActor in model.filesChanged(paths) }
            }
            defer { watcher.stop() }
            try await Task.sleep(for: .milliseconds(500))
            while model.isRenderingSelection { try await Task.sleep(for: .milliseconds(20)) }
            #expect(model.renders.values.allSatisfy { $0.generation == 1 })

            // Touching a source counts as an edit, without changing what it renders.
            let start = ContinuousClock.now
            try FileManager.default.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: package.appending(path: "Sources/FaultZoo/Faults.swift").path)
            while model.generation < 2 || model.isRenderingSelection || model.isRebuilding {
                try #require(
                    ContinuousClock.now - start < .seconds(60), "no new render within a minute")
                try await Task.sleep(for: .milliseconds(20))
            }
            let latency = ContinuousClock.now - start
            print("latency: edit → updated canvas: \(latency)")
            #expect(latency < .seconds(20))
            let key = ViewerModel.RenderKey(
                story: StoryID(module: "FaultZoo", group: "Faults", name: "Fine"),
                appearance: .light)
            #expect(model.renders[key]?.generation == 2)
            if case .image = model.renders[key]?.render {
            } else {
                Issue.record("expected an image, got \(String(describing: model.renders[key]))")
            }
        }
    }
#endif
