import Foundation

/// Admits renders to run at once, up to a limit, as long as they agree on the process's time
/// zone, which `Date.formatted()` and friends read instead of SwiftUI's environment. A render
/// that needs another time zone waits until those running finish. Renders are admitted in the
/// order they arrive, so none waits forever.
@MainActor final class RenderGate {
    /// The most renders that run at once.
    let limit: Int

    private var running = 0
    /// The time zone the running renders share, and the process's own before they set it.
    private var timeZone: (identifier: String, previous: String?)?
    private var waiting: [(timeZone: String, admit: CheckedContinuation<Void, Never>)] = []

    /// Sets the process's time zone, returning the one it replaces; and restores that.
    private let setTimeZone: (String) -> String?
    private let restoreTimeZone: (String?) -> Void

    init(
        limit: Int, setTimeZone: @escaping (String) -> String? = ProcessTimeZone.set,
        restoreTimeZone: @escaping (String?) -> Void = ProcessTimeZone.restore
    ) {
        self.limit = max(limit, 1)
        self.setTimeZone = setTimeZone
        self.restoreTimeZone = restoreTimeZone
    }

    /// Runs `body` once the gate admits a render in `timeZone`, with the process's time zone set
    /// to it.
    func run<T>(in timeZone: String, _ body: () async throws -> T) async throws -> T {
        if waiting.isEmpty, canAdmit(timeZone) {
            admit(timeZone)
        } else {
            await withCheckedContinuation { waiting.append((timeZone, $0)) }
        }
        defer { leave() }
        return try await body()
    }

    /// Renders running or waiting.
    var count: Int { running + waiting.count }

    private func canAdmit(_ identifier: String) -> Bool {
        running < limit && (timeZone == nil || timeZone?.identifier == identifier)
    }

    private func admit(_ identifier: String) {
        if timeZone == nil {
            timeZone = (identifier, setTimeZone(identifier))
        }
        running += 1
    }

    private func leave() {
        running -= 1
        if running == 0, let timeZone {
            restoreTimeZone(timeZone.previous)
            self.timeZone = nil
        }
        while let next = waiting.first, canAdmit(next.timeZone) {
            waiting.removeFirst()
            admit(next.timeZone)
            next.admit.resume()
        }
    }

    #if os(macOS)
        /// How many Mac renders run at once: `SWIFTBOOK_MAC_RENDERS`, or else 4 when capturing
        /// emulated and 1 through the window server, whose captures of windows on screen
        /// together haven't been checked against captures made one at a time.
        static func macLimit(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            capture: CaptureMethod? = try? CaptureMethod.current()
        ) -> Int {
            if let limit = environment["SWIFTBOOK_MAC_RENDERS"].flatMap(Int.init) {
                return max(limit, 1)
            }
            return capture == .windowServer ? 1 : 4
        }
    #endif
}
