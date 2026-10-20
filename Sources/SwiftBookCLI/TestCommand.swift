#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook test`: snapshot-tests stories on each device.
    struct TestCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "test",
            abstract: "Snapshot-test the package's stories on each device.",
            discussion: """
                The Mac runs through swift test, so #SwiftBookTests applies. Other devices \
                render in SwiftBook's own simulators and check every story, light and dark. \
                With no --device, tests every device that already has references, so coverage \
                follows what's committed. Ends by naming the failed snapshots, and exits with \
                status \(Exit.changed.rawValue) if any failed. To look at a story without \
                testing, use swiftbook render.
                """)

        @Option(
            name: [.customLong("device"), .customLong("platform")],
            help: ArgumentHelp(
                "A device to test on: mac, iphone, ipad, or tv. Repeat for several.",
                valueName: "device"))
        var devices: [Device] = []

        @Option(
            name: [.short, .long],
            help: ArgumentHelp(
                "The most simulators one device may use at once.",
                discussion:
                    "A run takes extra pooled simulators while they're free and enough stories remain to repay starting them. Defaults to the pool's size (SWIFTBOOK_SIMULATORS). 1 renders on one."
            ))
        var jobs: Int?

        @Option(help: "When to write references: missing, changed, all, or never.")
        var record: RecordMode?

        @Option(help: "Write a JUnit report of every snapshot to this file.")
        var junit: String?

        @Option(help: "The largest CIEDE2000 difference a pixel may have and still match.")
        var deltaE = ImageDiff.Tolerance().deltaE

        @Option(help: "The fraction of pixels allowed to change.")
        var changedRatio = ImageDiff.Tolerance().changedPixelRatio

        @Option(
            help: ArgumentHelp(
                "How many faint changed pixels count as noise rather than a change.",
                discussion:
                    "Liquid Glass and other GPU-rendered materials can settle a pixel differently from run to run."
            ))
        var noisePixels = ImageDiff.Tolerance().noisePixels

        @Option(help: "The largest CIEDE2000 difference a pixel may have and still count as noise.")
        var noiseDeltaE = ImageDiff.Tolerance().noiseDeltaE

        /// The tolerance the options describe. On the Mac, #SwiftBookTests sets its own.
        var tolerance: ImageDiff.Tolerance {
            var tolerance = ImageDiff.Tolerance()
            tolerance.deltaE = deltaE
            tolerance.changedPixelRatio = changedRatio
            tolerance.noisePixels = noisePixels
            tolerance.noiseDeltaE = noiseDeltaE
            return tolerance
        }

        func run() throws {
            let project: Project
            let mode: RecordMode
            do {
                project = try Project.current()
                mode = try record ?? RecordMode.fromEnvironment()
            } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
            // One message up front, rather than a failure for every snapshot.
            if let problem = Self.lfsProblem(project) {
                warn("swiftbook: \(problem)")
                throw Exit.broken.code
            }
            var devices = self.devices
            if devices.isEmpty {
                devices = Self.devicesWithReferences(in: project.store)
                if devices.isEmpty {
                    print("No references yet; testing the Mac. Pass --device to test others.")
                    devices = [.mac]
                }
            }
            var results = Results()
            for device in devices {
                print("Testing on \(device)…")
                // swift test writes to the same terminal; keep this line ahead of its output.
                fflush(stdout)
                do {
                    if device == .mac {
                        try results.add(Self.testMac(project, mode: mode))
                    } else {
                        try results.add(
                            Self.test(
                                project, on: device, mode: mode, tolerance: tolerance, jobs: jobs))
                    }
                } catch {
                    warn("swiftbook: \(device): \(error)")
                    throw Exit.broken.code
                }
            }
            if let junit {
                do {
                    try Data(results.junit().utf8).write(to: URL(filePath: junit))
                } catch {
                    warn("swiftbook: couldn't write \(junit): \(error)")
                    throw Exit.broken.code
                }
            }
            if let summary = results.failureSummary() { print(summary) }
            if results.failed { throw Exit.changed.code }
        }

        /// Why testing can't start, if any of `project`'s references are Git LFS pointers.
        static func lfsProblem(_ project: Project) -> String? {
            project.store.lfsProblem()
        }

        /// The devices with at least one reference in `store`, in a fixed order.
        static func devicesWithReferences(in store: SnapshotStore) -> [Device] {
            var found = Set<Device>()
            let enumerator = FileManager.default.enumerator(
                at: store.root, includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "png",
                    let prefix = url.lastPathComponent.split(separator: ".").first,
                    let device = Device(rawValue: String(prefix))
                else { continue }
                found.insert(device)
            }
            return Device.allCases.filter(found.contains)
        }

        /// The outcome of one snapshot.
        struct Result {
            var device: Device
            var subject: String
            /// The story it rendered, if it's one snapshot.
            var story: StoryID? = nil
            /// Why it failed, if it did.
            var failure: String?
        }

        struct Results {
            var all: [Result] = []
            var failed = false

            mutating func add(_ results: (results: [Result], failed: Bool)) {
                all += results.results
                failed = failed || results.failed
            }

            /// Closing lines that name every failed snapshot, so a long log needn't be searched
            /// for them, and give a command per device that renders the failed stories to look
            /// at. Nil when nothing failed.
            func failureSummary() -> String? {
                let failures = all.filter { $0.failure != nil }
                guard !failures.isEmpty else { return nil }
                var lines = [
                    "✗ \(failures.count) failed: "
                        + failures.map(\.subject).joined(separator: ", ")
                ]
                for device in Device.allCases {
                    var stories: [StoryID] = []
                    for case let story? in failures.filter({ $0.device == device }).map(\.story)
                    where !stories.contains(story) {
                        stories.append(story)
                    }
                    guard !stories.isEmpty else { continue }
                    let names = stories.map { Self.shellQuoted($0.description) }
                    lines.append(
                        "  To look at them: swiftbook render \(names.joined(separator: " ")) --device \(device)"
                    )
                }
                return lines.joined(separator: "\n")
            }

            /// `text` as one shell word, quoted only if it must be.
            static func shellQuoted(_ text: String) -> String {
                let plain = CharacterSet.alphanumerics.union(
                    CharacterSet(charactersIn: "/._-+=:,@%"))
                guard !text.isEmpty, text.unicodeScalars.allSatisfy(plain.contains) else {
                    // By scalar: a quote followed by a combining mark is one Character, which a
                    // replacement of the Character "'" would miss.
                    var quoted = String.UnicodeScalarView(["'"])
                    for scalar in text.unicodeScalars {
                        if scalar == "'" {
                            quoted.append(contentsOf: #"'\''"#.unicodeScalars)
                        } else {
                            quoted.append(scalar)
                        }
                    }
                    quoted.append("'")
                    return String(quoted)
                }
                return text
            }

            func junit() -> String {
                func escape(_ text: String) -> String {
                    text.replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "<", with: "&lt;")
                        .replacingOccurrences(of: "\"", with: "&quot;")
                }
                let failures = all.filter { $0.failure != nil }.count
                var lines = [
                    #"<?xml version="1.0" encoding="UTF-8"?>"#,
                    #"<testsuites name="swiftbook test" tests="\#(all.count)" failures="\#(failures)">"#,
                ]
                for device in Device.allCases {
                    let results = all.filter { $0.device == device }
                    guard !results.isEmpty else { continue }
                    let failed = results.filter { $0.failure != nil }.count
                    lines.append(
                        #"<testsuite name="\#(device)" tests="\#(results.count)" failures="\#(failed)">"#
                    )
                    for result in results {
                        let open =
                            #"<testcase classname="\#(device)" name="\#(escape(result.subject))""#
                        if let failure = result.failure {
                            lines.append(
                                #"\#(open)><failure message="\#(escape(failure.split(separator: "\n").first.map(String.init) ?? ""))">\#(escape(failure))</failure></testcase>"#
                            )
                        } else {
                            lines.append("\(open)/>")
                        }
                    }
                    lines.append("</testsuite>")
                }
                lines.append("</testsuites>")
                return lines.joined(separator: "\n")
            }
        }

        static let hints = SnapshotReport.Hints(
            accept: "swiftbook test --record changed", record: "swiftbook test --record missing")

        /// Renders every story on `device`, light and dark, and verifies each against its
        /// reference, on up to `jobs` pooled simulators at once.
        static func test(
            _ project: Project, on device: Device, mode: RecordMode,
            tolerance: ImageDiff.Tolerance = ImageDiff.Tolerance(), jobs: Int? = nil
        ) throws
            -> (results: [Result], failed: Bool)
        {
            try DeviceRun(
                project: project, device: device, mode: mode, tolerance: tolerance,
                jobs: jobs ?? SimulatorPool.size()
            ).run()
        }

        /// Runs the Mac's snapshots through `swift test`, where `#SwiftBookTests` applies.
        static func testMac(_ project: Project, mode: RecordMode) throws
            -> (results: [Result], failed: Bool)
        {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = ["swift", "test", "--filter", "SwiftBookSnapshots"]
            process.currentDirectoryURL = project.root
            process.environment = ProcessInfo.processInfo.environment.merging([
                RecordMode.environmentVariable: mode.rawValue
            ]) { $1 }
            try process.run()
            process.waitUntilExit()
            let failed = process.terminationStatus != 0
            // swift test reports each snapshot itself; the JUnit report gets one case for all.
            return (
                [
                    Result(
                        device: .mac, subject: "swift test --filter SwiftBookSnapshots",
                        failure: failed
                            ? "swift test exited with status \(process.terminationStatus)" : nil)
                ], failed
            )
        }
    }

    extension RecordMode: ExpressibleByArgument {}
#endif
