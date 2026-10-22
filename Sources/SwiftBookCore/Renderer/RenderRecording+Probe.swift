import ImpactProbe

extension RenderRecording {
    /// Runs `render`, recording the code it runs as this snapshot, declared in `fileID`. The
    /// snapshot also depends on the shared contexts `render` uses, which it may not run.
    @MainActor public func record<T>(
        declaredIn fileID: String?, _ render: () async throws -> T
    ) async rethrows -> T {
        let probe = ImpactProbe.start(test: test, declaredIn: fileID)
        PreviewModifiers.recording = (probe, scope)
        defer {
            PreviewModifiers.recording = nil
            probe.stop()
        }
        return try await render()
    }
}
