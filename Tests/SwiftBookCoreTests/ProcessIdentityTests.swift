#if os(macOS)
    import Foundation
    import Testing

    @testable import SwiftBookCore

    @Suite struct ProcessIdentityTests {
        @Test func tellsAProcessFromALaterOneWithItsPid() throws {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sleep")
            process.arguments = ["30"]
            try process.run()
            let identity = try #require(ProcessIdentity(pid: process.processIdentifier))
            #expect(identity.isRunning)
            // Another process under the same pid started at another time.
            #expect(
                !ProcessIdentity(pid: identity.pid, started: identity.started + 1).isRunning)

            process.terminate()
            let deadline = ContinuousClock.now + .seconds(5)
            while process.isRunning, ContinuousClock.now < deadline { usleep(10_000) }
            #expect(!identity.isRunning)
        }

        @Test func findsNoProcessForAnUnusedPid() {
            #expect(ProcessIdentity(pid: -1) == nil)
        }
    }
#endif
