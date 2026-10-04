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
                follows what's committed. Exits with status \(Exit.changed.rawValue) if a \
                snapshot fails.
                """)

        @Option(
            name: [.customLong("device"), .customLong("platform")],
            help: ArgumentHelp(
                "A device to test on: mac, iphone, ipad, or tv. Repeat for several.",
                valueName: "device"))
        var devices: [Device] = []

        @Option(help: "When to write references: missing, changed, all, or never.")
        var record: RecordMode?

        @Option(help: "Write a JUnit report of every snapshot to this file.")
        var junit: String?

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
                        try results.add(Self.test(project, on: device, mode: mode))
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
            if results.failed { throw Exit.changed.code }
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
        /// reference.
        static func test(_ project: Project, on device: Device, mode: RecordMode) throws
            -> (results: [Result], failed: Bool)
        {
            let renderer = try Renderers.start(for: project, on: device)
            defer { renderer.shutdown() }
            let stories = try renderer.stories()
            var results: [Result] = []
            var failed = false
            var counts = (matched: 0, new: 0, rerecorded: 0, failed: 0)
            for story in stories {
                for appearance in RenderEnvironment.Appearance.allCases {
                    var environment = RenderEnvironment.standard(for: device)
                    environment.appearance = appearance
                    let subject =
                        "\(story.id) (\(SnapshotStore.variantName(device: device, environment: environment)))"
                    do {
                        let png = try renderer.render(story.id, in: environment)
                        let snapshot = try Snapshot(
                            png: png, story: story.id, device: device, environment: environment)
                        let verification = try project.store.verify(snapshot, mode: mode)
                        guard
                            let report = try SnapshotReport(
                                verification, of: snapshot, mode: mode, store: project.store,
                                hints: hints)
                        else {
                            counts.matched += 1
                            results.append(Result(device: device, subject: subject))
                            continue
                        }
                        print((report.severity == .failure ? "✗ " : "! ") + report.message + "\n")
                        switch report.kind {
                        case .new: counts.new += 1
                        case .changed: counts.rerecorded += 1
                        default: counts.failed += 1
                        }
                        if report.severity == .failure {
                            failed = true
                            results.append(
                                Result(device: device, subject: subject, failure: report.message))
                        } else {
                            results.append(Result(device: device, subject: subject))
                        }
                    } catch {
                        failed = true
                        counts.failed += 1
                        print("✗ \(subject): \(error)\n")
                        results.append(
                            Result(device: device, subject: subject, failure: "\(error)"))
                    }
                }
            }
            print(
                "\(device): \(results.count) snapshots: \(counts.matched) matched, \(counts.new) new, \(counts.rerecorded) re-recorded, \(counts.failed) failed."
                    + (renderer.restarts > 0
                        ? " The renderer crashed or hung and was restarted \(renderer.restarts) times."
                        : "")
            )
            return (results, failed)
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
