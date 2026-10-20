/// How long a story with a ``SwiftBookConfiguration/settling`` entry must hold still before
/// it's captured.
///
/// A view that draws in stages, such as a `PDFView`, can hold still between them, and on a
/// loaded machine its stages take longer. So a hold counts captures as well as time: the story
/// must hold still for its duration, and through as many identical captures in a row as that
/// duration spans on an idle machine. Idle, the two end together. Loaded, captures come slower,
/// so the hold stretches with the same slowness that delays the view.
struct Hold: Sendable {
    let duration: Duration

    /// About how often an idle machine captures a render.
    static let idleCaptureInterval = Duration.milliseconds(50)

    /// How long a held story may keep changing before it fails as still changing: long enough
    /// to outlast load, so only a story that never settles, or hangs, fails.
    static let ceiling = Duration.seconds(30)

    /// Identical captures in a row the hold needs: none without one.
    var captures: Int {
        duration > .zero ? Int((duration / Self.idleCaptureInterval).rounded(.up)) : 0
    }

    /// Whether a run of `identical` captures in a row, held still for `stable`, satisfies it.
    func isSatisfied(stable: Duration, identical: Int) -> Bool {
        stable >= duration && identical >= captures
    }

    /// How long a render may take to settle: `timeout` for a story without a hold, and the
    /// ceiling for one with a hold.
    func timeout(otherwise timeout: Duration) -> Duration {
        duration > .zero ? max(timeout, Self.ceiling) : timeout
    }
}
