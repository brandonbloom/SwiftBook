import Foundation
import Testing

@testable import SwiftBookCore

@MainActor @Suite struct RenderGateTests {
    /// What the gate let run: how many at once, in which time zones, and in what order, with
    /// the time zone it set in place of the process's.
    @MainActor final class Log {
        var zone: String? = "Original"
        var running: [String] = []
        var mostAtOnce = 0
        var overlappedZones = false
        var wrongZone = false
        var started: [Int] = []
        var finished = 0

        func run(_ index: Int, in zone: String, gate: RenderGate) async throws {
            try await gate.run(in: zone) {
                started.append(index)
                running.append(zone)
                mostAtOnce = max(mostAtOnce, running.count)
                if Set(running).count > 1 { overlappedZones = true }
                if self.zone != zone { wrongZone = true }
                try await Task.sleep(for: .milliseconds(20))
                running.remove(at: running.firstIndex(of: zone)!)
                finished += 1
            }
        }
    }

    func gate(limit: Int, log: Log) -> RenderGate {
        RenderGate(
            limit: limit,
            setTimeZone: { zone in
                defer { log.zone = zone }
                return log.zone
            },
            restoreTimeZone: { log.zone = $0 })
    }

    @Test func runsUpToTheLimitAtOnce() async throws {
        let log = Log()
        let gate = gate(limit: 3, log: log)
        try await withThrowingTaskGroup { group in
            for index in 0..<10 {
                group.addTask { try await log.run(index, in: "UTC", gate: gate) }
            }
            try await group.waitForAll()
        }
        #expect(log.mostAtOnce == 3)
        #expect(log.started.count == 10)
        #expect(!log.wrongZone)
    }

    @Test func neverOverlapsTimeZonesAndKeepsArrivalOrder() async throws {
        let log = Log()
        let gate = gate(limit: 4, log: log)
        let zones = ["UTC", "UTC", "Asia/Tokyo", "UTC", "Asia/Tokyo", "Asia/Tokyo", "UTC"]
        try await withThrowingTaskGroup { group in
            for (index, zone) in zones.enumerated() {
                group.addTask { try await log.run(index, in: zone, gate: gate) }
                // Arrive in order: each reaches the gate before the next starts, or finishes.
                while gate.count + log.finished < index + 1 { await Task.yield() }
            }
            try await group.waitForAll()
        }
        #expect(!log.overlappedZones)
        #expect(!log.wrongZone)
        #expect(log.started == Array(zones.indices))
        // The process's own time zone comes back once nothing runs.
        #expect(log.zone == "Original")
    }

    #if os(macOS)
        @Test func choosesALimitByCaptureMethod() {
            #expect(RenderGate.macLimit(environment: [:], capture: .emulated) == 4)
            #expect(RenderGate.macLimit(environment: [:], capture: .windowServer) == 1)
            #expect(
                RenderGate.macLimit(
                    environment: ["SWIFTBOOK_MAC_RENDERS": "8"], capture: .windowServer) == 8)
            #expect(RenderGate.macLimit(environment: ["SWIFTBOOK_MAC_RENDERS": "0"]) == 1)
        }
    #endif
}
