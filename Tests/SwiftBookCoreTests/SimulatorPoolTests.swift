#if os(macOS)
    import Foundation
    import Testing

    @testable import SwiftBookCore

    @Suite struct SimulatorPoolTests {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SimulatorPoolTests-\(UUID())", directoryHint: .isDirectory)

        @Test func sizesThePoolByMemoryAndCores() {
            let gigabyte: UInt64 = 1 << 30
            // Half of 128 GB fits 16 at 4 GB each; 12 performance cores allow 6.
            #expect(
                SimulatorPool.size(environment: [:], memory: 128 * gigabyte, performanceCores: 12)
                    == 6)
            // Half of 16 GB fits 2.
            #expect(
                SimulatorPool.size(environment: [:], memory: 16 * gigabyte, performanceCores: 12)
                    == 2)
            // Never none.
            #expect(
                SimulatorPool.size(environment: [:], memory: 4 * gigabyte, performanceCores: 1)
                    == 1)
            #expect(
                SimulatorPool.size(
                    environment: [SimulatorPool.sizeVariable: "9"], memory: 4 * gigabyte,
                    performanceCores: 1) == 9)
        }

        @Test func leasesEachSimulatorToOneHolderAtATime() throws {
            let first = try #require(try SimulatorPool.claim(.iphone, size: 2, in: directory))
            let second = try #require(try SimulatorPool.claim(.iphone, size: 2, in: directory))
            #expect(first.number == 1)
            #expect(second.number == 2)
            #expect(try SimulatorPool.claim(.iphone, size: 2, in: directory) == nil)
            // Other device classes have pools of their own.
            #expect(try SimulatorPool.claim(.ipad, size: 2, in: directory)?.number == 1)

            first.lock.release()
            #expect(try SimulatorPool.claim(.iphone, size: 2, in: directory)?.number == 1)
        }

        @Test func shutsAnExtraSimulatorDownOnceIdle() throws {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            var shutdowns = 0
            func shutDownWhenIdle() throws -> Bool {
                try SimulatorPool.shutDownWhenIdle(
                    .iphone, number: 2, idle: .milliseconds(300), in: directory
                ) { shutdowns += 1 }
            }

            // Released just now: it waits out the idle time first.
            SimulatorPool.markReleased(.iphone, number: 2, in: directory)
            let start = ContinuousClock.now
            #expect(try shutDownWhenIdle())
            #expect(ContinuousClock.now - start >= .milliseconds(300))
            #expect(shutdowns == 1)

            // Leased again: the run holding it arranges the next shutdown.
            let held = try #require(try SimulatorPool.claim(.iphone, size: 2, in: directory))
            let again = try #require(try SimulatorPool.claim(.iphone, size: 2, in: directory))
            #expect(again.number == 2)
            #expect(try !shutDownWhenIdle())
            #expect(shutdowns == 1)
            held.lock.release()
            again.lock.release()
        }
    }
#endif
