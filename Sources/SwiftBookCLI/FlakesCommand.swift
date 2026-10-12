#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook flakes`: finds stories that render differently from run to run.
    struct FlakesCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "flakes",
            abstract: "Find stories that render differently from run to run.",
            discussion: """
                Renders each story, light and dark, several times, each run in a fresh renderer, \
                and reports the snapshots whose renders disagree: how many ways they rendered, \
                how often, and where they differ. It compares renders with each other, not with \
                references, so it works on stories that have none yet. Images of each variant \
                and their differences go to .build/swiftbook/flakes. Exits with status \
                \(Exit.changed.rawValue) if any snapshot is flaky.
                """)

        @Argument(help: "Stories to check, as Module/Group/Name. All of them by default.")
        var stories: [String] = []

        @Option(name: [.customLong("device"), .customLong("platform")], help: deviceHelp)
        var device = Device.mac

        @Option(help: "How many times to render each snapshot.")
        var runs = 10

        func run() throws {
            let flakes: [FlakeFinder.Flake]
            let checked: Int
            let project: Project
            do {
                project = try Project.current()
                (flakes, checked) = try find(in: project)
            } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
            let artifacts = Self.artifacts(for: project)
            try? FileManager.default.removeItem(at: artifacts)
            for flake in flakes {
                print(Self.describe(flake, runs: runs, artifacts: artifacts) + "\n")
            }
            if flakes.isEmpty {
                print(
                    "No flaky snapshots: \(checked) snapshots rendered the same way \(runs) times.")
            } else {
                print("\(flakes.count) of \(checked) snapshots are flaky in \(runs) runs.")
                throw Exit.changed.code
            }
        }

        /// Renders the chosen stories `runs` times, each run in a fresh renderer.
        private func find(in project: Project) throws -> ([FlakeFinder.Flake], Int) {
            guard runs >= 2 else { throw Failure(description: "--runs must be at least 2") }
            // Built once; each run launches it fresh, as a CI run would.
            let start: () throws -> RestartingRenderer
            var lease: SimulatorLease?
            switch device {
            case .mac:
                FileHandle.standardError.write(Data("Building the renderer…\n".utf8))
                let executable = try RendererHost(package: project.root).build()
                start = { try RestartingRenderer { try RendererProcess(executable: executable) } }
            case .iphone, .ipad, .tv:
                let app = try Renderers.buildApp(for: project, on: device)
                let leased = try SimulatorPool.lease(
                    for: device, waiting: Renderers.progress,
                    keepWarm: SimulatorIdleCommand.start)
                lease = leased
                start = {
                    try RestartingRenderer {
                        try RendererProcess(
                            app: app.url, bundleID: app.bundleID, in: leased.simulator)
                    }
                }
            case .catalyst:
                throw Failure(description: "Mac Catalyst rendering isn't supported yet.")
            }
            defer { lease?.release() }

            var finder = FlakeFinder()
            var selected: [StoryID] = []
            for run in 1...runs {
                FileHandle.standardError.write(Data("Run \(run) of \(runs)…\n".utf8))
                let renderer = try start()
                defer { renderer.shutdown() }
                if selected.isEmpty {
                    let all = try renderer.stories().map(\.id)
                    selected =
                        stories.isEmpty
                        ? all
                        : try stories.map { name in
                            guard let story = all.first(where: { $0.description == name }) else {
                                throw Failure(description: "no story \(name)")
                            }
                            return story
                        }
                }
                for story in selected {
                    for appearance in RenderEnvironment.Appearance.allCases {
                        var environment = RenderEnvironment.standard(for: device)
                        environment.appearance = appearance
                        let subject =
                            "\(story) (\(SnapshotStore.variantName(device: device, environment: environment)))"
                        do {
                            let rendered = try renderer.renderImage(story, in: environment)
                            finder.add(
                                rendered.png, glassRegions: rendered.glassRegions, for: subject)
                        } catch {
                            finder.addFailure("\(error)", for: subject)
                        }
                    }
                }
            }
            return (
                try finder.flakes(), selected.count * RenderEnvironment.Appearance.allCases.count
            )
        }

        /// Where images of flaky snapshots go.
        static func artifacts(for project: Project) -> URL {
            (ProcessInfo.processInfo.environment["SWIFTBOOK_ARTIFACTS"].map { URL(filePath: $0) }
                ?? project.root.appending(path: ".build/swiftbook"))
                .appending(path: "flakes", directoryHint: .isDirectory)
        }

        /// A flaky snapshot, for people: its variants, how they differ, and where to look. Writes
        /// each variant, and its difference from the most common one, under `artifacts`.
        static func describe(_ flake: FlakeFinder.Flake, runs: Int, artifacts: URL) -> String {
            let counts = flake.variants.map { String($0.count) }
            var lines = [
                "~ \(flake.subject): rendered \(flake.variants.count) ways in \(runs) runs (\(counts.joined(separator: ", ")))"
                    + (flake.failures > 0 ? ", and failed in \(flake.failures)" : "")
            ]
            for (offset, difference) in flake.differences.enumerated() {
                let deltaE = difference.maxDeltaE.formatted(.number.precision(.fractionLength(1)))
                var line =
                    "    Variant \(offset + 2): \(flake.differingPixels[offset]) pixels differ from variant 1, ΔE up to \(deltaE). "
                if !difference.matches {
                    line += "A comparison would fail"
                    if let bounds = difference.changedBounds {
                        line +=
                            ": \(difference.changedPixels) changed within \(Int(bounds.width))×\(Int(bounds.height)) pixels at (\(Int(bounds.minX)), \(Int(bounds.minY)))"
                    }
                    line += "."
                } else if difference.glassNoisePixels > 0 {
                    line += "A comparison would match: the rest is Liquid Glass noise."
                } else {
                    line += "A comparison would match: too faint or too few to count."
                }
                lines.append(line)
            }
            if let failure = flake.failure {
                lines.append("    Failed with: \(failure.split(separator: "\n").first ?? "")")
            }
            // A directory per snapshot: the subject's story, then a file per variant.
            let stem = artifacts.appending(
                path: flake.subject.replacingOccurrences(of: " (", with: "/")
                    .replacingOccurrences(of: ")", with: ""))
            if (try? FileManager.default.createDirectory(
                at: stem, withIntermediateDirectories: true)) != nil
            {
                for (offset, variant) in flake.variants.enumerated() {
                    try? variant.png.write(to: stem.appending(path: "variant-\(offset + 1).png"))
                }
                for (offset, difference) in flake.differences.enumerated() {
                    try? difference.pngData()?.write(
                        to: stem.appending(path: "variant-\(offset + 2).diff.png"))
                }
                lines.append("    Images: \(stem.path)")
            }
            return lines.joined(separator: "\n")
        }
    }
#endif
