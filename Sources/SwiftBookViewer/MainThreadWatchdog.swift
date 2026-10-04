#if os(macOS)
    import Foundation

    /// Watches the main thread for stalls: stretches when it couldn't handle events, so the
    /// viewer stopped responding.
    ///
    /// A background thread asks the main queue to answer every 50 ms and times the answer. Stalls
    /// past `threshold` go to standard error, which `swiftbook view` sends to the viewer's log.
    /// It's for scripted sessions: while it runs, App Nap is off, since a napping app answers late
    /// without being busy, and the pings themselves cost energy.
    final class MainThreadWatchdog: @unchecked Sendable {
        // Unchecked: `lock` guards the mutable state.

        static let shared = MainThreadWatchdog()

        let threshold = Duration.milliseconds(250)
        private let lock = NSLock()
        private var _longest = Duration.zero
        private var started = false
        private var activity: NSObjectProtocol?

        /// The longest stall so far.
        var longest: Duration { lock.withLock { _longest } }

        func start() {
            guard
                lock.withLock({
                    defer { started = true }
                    return !started
                })
            else { return }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical],
                reason: "Timing the main thread's responses")
            Thread.detachNewThread { [self] in
                while true {
                    let asked = ContinuousClock.now
                    let answered = DispatchSemaphore(value: 0)
                    // Timed on the main thread, so this thread waking late doesn't count.
                    nonisolated(unsafe) var ran = asked
                    DispatchQueue.main.async {
                        ran = ContinuousClock.now
                        answered.signal()
                    }
                    answered.wait()
                    let stall = ran - asked
                    lock.withLock { _longest = max(_longest, stall) }
                    if stall > threshold {
                        let milliseconds =
                            stall.components.seconds * 1000
                            + stall.components.attoseconds / 1_000_000_000_000_000
                        FileHandle.standardError.write(
                            Data(
                                "swiftbook-viewer: main thread stalled for \(milliseconds) ms\n"
                                    .utf8))
                    }
                    Thread.sleep(forTimeInterval: 0.05)
                }
            }
        }
    }
#endif
