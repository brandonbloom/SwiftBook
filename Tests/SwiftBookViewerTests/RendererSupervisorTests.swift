#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookViewer

    /// The supervisor against real renderers of previews that crash, hang, and dawdle.
    @Suite(.serialized) struct RendererSupervisorTests {
        static let faultZoo = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/FaultZoo", directoryHint: .isDirectory)

        static func story(_ name: String) -> StoryID {
            StoryID(module: "FaultZoo", group: "Faults", name: name)
        }

        @Test func survivesCrashesAndHangsAndSwapsGenerations() async throws {
            let supervisor = try await RendererSupervisor.start(
                for: Self.faultZoo, renderTimeout: .seconds(3))
            #expect(await supervisor.generation() == 1)
            let stories = try await supervisor.stories().map(\.name)
            #expect(stories == ["Fine", "Crashes", "Hangs", "Slow"])
            let fine = try await supervisor.render(Self.story("Fine"), in: RenderEnvironment())

            // A crash fails only its own render.
            await #expect {
                try await supervisor.render(Self.story("Crashes"), in: RenderEnvironment())
            } throws: { error in
                let description = String(describing: error)
                return description.contains("exited") && description.contains("restarted")
            }
            #expect(
                try await supervisor.render(Self.story("Fine"), in: RenderEnvironment()) == fine)

            // So does a hang, after the timeout.
            let start = ContinuousClock.now
            await #expect {
                try await supervisor.render(Self.story("Hangs"), in: RenderEnvironment())
            } throws: { String(describing: $0).contains("took longer than") }
            #expect(ContinuousClock.now - start < .seconds(10))
            #expect(
                try await supervisor.render(Self.story("Fine"), in: RenderEnvironment()) == fine)

            // A slow story within the timeout is just slow.
            _ = try await supervisor.render(Self.story("Slow"), in: RenderEnvironment())

            // A rebuild swaps to a fresh renderer of the new build.
            #expect(try await supervisor.rebuild() == 2)
            #expect(
                try await supervisor.render(Self.story("Fine"), in: RenderEnvironment()) == fine)
        }
    }
#endif
