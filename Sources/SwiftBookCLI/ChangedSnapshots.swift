#if os(macOS)
    import CryptoKit
    import Foundation
    import ImpactAnalysis
    import SwiftBookCore

    /// Experimental: which snapshots `swiftbook test --changed` renders on a device, and what it
    /// remembers of each run.
    ///
    /// The renderer is built instrumented, into a build directory of its own, and records the code
    /// each snapshot's render runs. SwiftImpact compares that with the next build, and says which
    /// snapshots a change may have impacted. SwiftBook adds what only it knows: a snapshot renders
    /// again if it failed last time, if its reference changed, or if the run's settings did.
    struct ChangedSnapshots {
        let project: Project
        let device: Device

        /// The instrumented build, shared by every device. Its past results go with it.
        var buildDirectory: URL {
            project.root.appending(path: ".build/swiftbook/changed", directoryHint: .isDirectory)
        }

        /// The renderer's host, building into ``buildDirectory`` with SwiftImpact's arguments.
        var host: RendererHost {
            RendererHost(
                package: project.root, scratchPath: buildDirectory,
                buildArguments: ImpactAnalysis.buildArguments)
        }

        /// What to launch renderers with, so they record into ``buildDirectory``.
        var environment: [String: String] { ImpactAnalysis.environment(for: buildDirectory) }

        /// What the render of `story` in `appearance` records.
        func recording(_ story: StoryID, _ appearance: RenderEnvironment.Appearance)
            -> RenderRecording
        {
            RenderRecording(
                test: "\(device.rawValue)/\(appearance.rawValue)/\(story)", scope: device.rawValue)
        }

        /// What a past run found for one snapshot.
        struct Outcome: Codable, Equatable {
            var passed: Bool
            /// A hash of the snapshot's reference after the run, `nil` if it had none.
            var reference: String?
        }

        /// The device's past results, and the settings they hold for.
        struct Past: Codable {
            var settings: String
            var outcomes: [String: Outcome]
        }

        var pastURL: URL { buildDirectory.appending(path: "swiftbook-\(device.rawValue).json") }

        func past() -> Past? {
            (try? Data(contentsOf: pastURL)).flatMap {
                try? JSONDecoder().decode(Past.self, from: $0)
            }
        }

        func save(_ past: Past) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            try encoder.encode(past).write(to: pastURL, options: .atomic)
        }

        /// What the snapshots' results depend on besides the code and references: this
        /// `swiftbook`, which compares them, the OS the renderer runs, the capture method, and the
        /// tolerance.
        static func settings(osVersion: String?, tolerance: ImageDiff.Tolerance) -> String {
            let executable = Bundle.main.executableURL.flatMap {
                try? FileManager.default.attributesOfItem(atPath: $0.path)
            }
            let built = (executable?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let capture = (try? CaptureMethod.current())?.rawValue ?? "unknown"
            return
                "swiftbook \(built); os \(osVersion ?? "unknown"); capture \(capture); \(tolerance)"
        }

        /// A hash of the reference at `url`, `nil` if there's none.
        static func referenceHash(_ url: URL) -> String? {
            (try? Data(contentsOf: url)).map {
                SHA256.hash(data: $0).prefix(16).map { String(format: "%02x", $0) }.joined()
            }
        }

        /// Why a snapshot needs to render, or `nil` if its last result still holds.
        ///
        /// `impact` is SwiftImpact's explanation if a change may have impacted it, `nil` if not.
        static func reason(
            impact: String?, past: Outcome?, reference: String?, settingsChanged: Bool
        ) -> String? {
            if settingsChanged { return "the run's settings changed" }
            guard let past else { return "it has no past result" }
            if !past.passed { return "it failed last time" }
            if past.reference != reference { return "its reference changed" }
            return impact
        }
    }
#endif
