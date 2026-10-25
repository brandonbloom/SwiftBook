#if os(macOS)
    import Foundation
    import Testing

    @testable import SwiftBookCore

    @Suite struct SimulatorCrashesTests {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "SimulatorCrashesTests-\(UUID())", directoryHint: .isDirectory)
        let udid = "7B9CE55E-7BB6-4909-8E17-D569B6F82308"
        let now = Date(timeIntervalSince1970: 1_790_000_000)

        /// Writes a crash report for `process` in simulator `udid`, made `ago` seconds before `now`.
        func report(_ process: String, in udid: String, ago: TimeInterval, index: Int) throws {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let file = directory.appending(path: "\(process)-2026-10-25-09\(1000 + index).ips")
            try Data(
                #"{"bug_type":"309"} {"coalitionName" : "com.apple.CoreSimulator.SimDevice.\#(udid)"}"#
                    .utf8
            ).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: now.addingTimeInterval(-ago)], ofItemAtPath: file.path)
        }

        @Test func findsAServiceThatCrashesOverAndOver() throws {
            for index in 0..<25 { try report("PosterBoard", in: udid, ago: 60, index: index) }
            // Now and then isn't a loop: every 20 minutes or so.
            for index in 0..<3 {
                try report("intelligencetasksd", in: udid, ago: 1200 * Double(index), index: index)
            }
            // SwiftBook's renderer crashes with stories, not with the simulator.
            for index in 0..<9 { try report(RendererHost.name, in: udid, ago: 60, index: index) }
            // Another simulator's crashes are its own.
            let other = "9FF06009-4DA9-4534-921F-F96E4A25A7B2"
            for index in 0..<9 { try report("SpringBoard", in: other, ago: 60, index: index) }
            #expect(
                SimulatorCrashes.loops(udid: udid, now: now, in: directory) == ["PosterBoard"])
            #expect(
                SimulatorCrashes.loops(udid: other, now: now, in: directory) == ["SpringBoard"])
        }

        @Test func forgetsCrashesBeforeTheWindowOrTheLastErase() throws {
            for index in 0..<10 { try report("PosterBoard", in: udid, ago: 7200, index: index) }
            #expect(SimulatorCrashes.loops(udid: udid, now: now, in: directory).isEmpty)
            for index in 10..<20 { try report("PosterBoard", in: udid, ago: 600, index: index) }
            #expect(!SimulatorCrashes.loops(udid: udid, now: now, in: directory).isEmpty)
            let erased = now.addingTimeInterval(-300)
            #expect(
                SimulatorCrashes.loops(udid: udid, since: erased, now: now, in: directory).isEmpty)
        }

        @Test func namesTheProcessFromTheReportsName() {
            #expect(
                SimulatorCrashes.process(named: "PosterBoard-2026-10-25-091146.ips")
                    == "PosterBoard")
            #expect(
                SimulatorCrashes.process(
                    named: "AppIntentsLiveEntityService-2026-10-25-091146.000.ips")
                    == "AppIntentsLiveEntityService")
            #expect(SimulatorCrashes.process(named: "notes.txt") == nil)
        }
    }
#endif
