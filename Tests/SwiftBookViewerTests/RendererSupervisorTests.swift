#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookViewer

    /// The supervisor and live reloading, against real renderers of FaultZoo, whose previews
    /// crash, hang, and dawdle. Serialized: the tests share FaultZoo's renderer build, and one of
    /// them edits a source, which would load the machine and rebuild under the other.
    @MainActor @Suite(.serialized) struct RendererSupervisorTests {
        static let faultZoo = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/FaultZoo", directoryHint: .isDirectory)

        static func story(_ name: String) -> StoryID {
            StoryID(module: "FaultZoo", group: "Faults", name: name)
        }

        @Test func survivesCrashesAndHangsAndSwapsGenerations() async throws {
            // Generous enough for a loaded machine; the hang still has to hit it.
            let supervisor = try await RendererSupervisor.start(
                for: Self.faultZoo, renderTimeout: .seconds(8))
            #expect(await supervisor.generation() == 1)
            let stories = try await supervisor.stories().map(\.name)
            #expect(stories == ["Fine", "Crashes", "Hangs", "Slow"])
            let fine = try await supervisor.render(
                Self.story("Fine"), in: RenderEnvironment(), background: false)

            // A crash fails only its own render.
            await #expect {
                try await supervisor.render(
                    Self.story("Crashes"), in: RenderEnvironment(), background: false)
            } throws: { error in
                let description = String(describing: error)
                return description.contains("exited") && description.contains("restarted")
            }
            #expect(
                try await supervisor.render(
                    Self.story("Fine"), in: RenderEnvironment(), background: false) == fine)

            // So does a hang, after the timeout.
            let start = ContinuousClock.now
            await #expect {
                try await supervisor.render(
                    Self.story("Hangs"), in: RenderEnvironment(), background: false)
            } throws: { String(describing: $0).contains("took longer than") }
            #expect(ContinuousClock.now - start < .seconds(20))
            #expect(
                try await supervisor.render(
                    Self.story("Fine"), in: RenderEnvironment(), background: false) == fine)

            // A slow story within the timeout is just slow.
            _ = try await supervisor.render(
                Self.story("Slow"), in: RenderEnvironment(), background: false)

            // A rebuild swaps to a fresh renderer of the new build.
            #expect(try await supervisor.rebuild() == 2)
            #expect(
                try await supervisor.render(
                    Self.story("Fine"), in: RenderEnvironment(), background: false) == fine)
        }

        /// An edit reaching the canvas, through a real file watcher, build, and renderer.
        @Test func anEditRerendersTheSelection() async throws {
            let package = Self.faultZoo
            let model = ViewerModel(package: package)
            // FaultZoo hangs on purpose: rendering ahead would reach that story, and a reload
            // would wait out its background timeout. This measures an ordinary edit.
            model.rendersAhead = false
            await model.start()
            #expect(model.status == .ready)
            model.selection = Self.story("Fine")
            let watcher = FileWatcher(directory: package) { paths in
                Task { @MainActor in model.filesChanged(paths) }
            }
            defer { watcher.stop() }
            try await Task.sleep(for: .milliseconds(500))
            while model.isRenderingSelection { try await Task.sleep(for: .milliseconds(20)) }
            #expect(model.renders.values.allSatisfy { $0.generation == 1 })

            // Touching a source counts as an edit, without changing what it renders. FSEvents can
            // miss a change made just after its stream starts, so touch again until a rebuild
            // begins.
            let source = package.appending(path: "Sources/FaultZoo/Faults.swift").path
            let start = ContinuousClock.now
            var touched = ContinuousClock.now - .seconds(10)
            while model.generation < 2 || model.isRenderingSelection || model.isRebuilding {
                try #require(
                    ContinuousClock.now - start < .seconds(60), "no new render within a minute")
                if model.generation < 2, !model.isRebuilding,
                    ContinuousClock.now - touched > .seconds(3)
                {
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date()], ofItemAtPath: source)
                    touched = ContinuousClock.now
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            let latency = ContinuousClock.now - start
            print("latency: edit → updated canvas: \(latency)")
            #expect(latency < .seconds(20))
            let key = ViewerModel.RenderKey(story: Self.story("Fine"), variant: .init())
            #expect(model.renders[key]?.generation == 2)
            if case .image = model.renders[key]?.render {
            } else {
                Issue.record("expected an image, got \(String(describing: model.renders[key]))")
            }
        }
    }
#endif
