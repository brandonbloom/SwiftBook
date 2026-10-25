#if os(macOS)
    import Foundation

    /// Crash loops of system services in a simulator, found in the crash reports macOS writes.
    ///
    /// A simulator's services can crash over and over, as PosterBoard does when its data goes bad,
    /// each crash writing a report. Erasing the simulator stops it. A service that crashes now and
    /// then, as some do every 20 minutes or so, isn't looping.
    public enum SimulatorCrashes {
        /// Where macOS writes crash reports, including those of simulated processes.
        public static var reports: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Library/Logs/DiagnosticReports", directoryHint: .isDirectory)
        }

        /// How many crashes of one process within ``window`` make a loop.
        static let threshold = 5
        /// How far back crashes count.
        static let window: TimeInterval = 3600

        /// The processes that crashed at least ``threshold`` times in simulator `udid` since
        /// `since`, or in the last ``window`` if that's later, most crashes first. SwiftBook's own
        /// renderer is left out: it crashes with the stories it renders.
        public static func loops(
            udid: String, since: Date = .distantPast, now: Date = Date(),
            in directory: URL = reports
        ) -> [String] {
            let start = max(since, now.addingTimeInterval(-window))
            let counts = crashes(udid: udid, since: start, in: directory)
            return counts.filter { $0.value >= threshold }
                .sorted { ($1.value, $0.key) < ($0.value, $1.key) }.map(\.key)
        }

        /// How many crash reports each process has in simulator `udid` since `since`.
        static func crashes(udid: String, since: Date, in directory: URL) -> [String: Int] {
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))
                ?? []
            let device = Data("SimDevice.\(udid)".utf8)
            var counts: [String: Int] = [:]
            for file in files where file.pathExtension == "ips" {
                guard
                    let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate, modified >= since,
                    let process = process(named: file.lastPathComponent),
                    process != RendererHost.name,
                    let handle = try? FileHandle(forReadingFrom: file)
                else { continue }
                // The header and the start of the report name the simulator's coalition.
                let head = (try? handle.read(upToCount: 16_384)) ?? Data()
                try? handle.close()
                if head.range(of: device) != nil { counts[process, default: 0] += 1 }
            }
            return counts
        }

        /// The process a report is for, from its name: `PosterBoard-2026-10-25-091146.ips`.
        static func process(named file: String) -> String? {
            guard
                let match = file.firstMatch(
                    of: /^(.+)-\d{4}-\d{2}-\d{2}-\d{6}(?:\.\d+)?\.ips$/)
            else { return nil }
            return String(match.1)
        }
    }
#endif
