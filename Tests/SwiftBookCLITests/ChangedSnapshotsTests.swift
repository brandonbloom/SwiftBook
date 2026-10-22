#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookCLI

    @Suite struct ChangedSnapshotsTests {
        typealias Outcome = ChangedSnapshots.Outcome

        func reason(
            impact: String? = nil, past: Outcome? = Outcome(passed: true, reference: "a"),
            reference: String? = "a", settingsChanged: Bool = false
        ) -> String? {
            ChangedSnapshots.reason(
                impact: impact, past: past, reference: reference,
                settingsChanged: settingsChanged)
        }

        @Test func skipsWhenItsLastResultHolds() {
            #expect(reason() == nil)
        }

        @Test func rendersWhenAnythingItsResultDependsOnChanged() {
            #expect(reason(impact: "M/A.swift changed") == "M/A.swift changed")
            #expect(reason(past: nil) == "it has no past result")
            #expect(reason(past: Outcome(passed: false, reference: "a")) == "it failed last time")
            #expect(reason(reference: "b") == "its reference changed")
            #expect(reason(reference: nil) == "its reference changed")
            #expect(reason(settingsChanged: true) == "the run's settings changed")
        }

        /// A scratch package.
        func project() throws -> Project {
            let root = FileManager.default.temporaryDirectory.appending(
                path: "ChangedSnapshotsTests-\(UUID())", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data("// swift-tools-version: 6.2\n".utf8).write(
                to: root.appending(path: "Package.swift"))
            return try Project(containing: root)
        }

        @Test func namesEachSnapshotByDeviceAndAppearance() throws {
            let project = try project()
            let story = StoryID(module: "M", group: "G", name: "S")
            let mac = ChangedSnapshots(project: project, device: .mac)
            let iphone = ChangedSnapshots(project: project, device: .iphone)
            let tests = [
                mac.recording(story, .light), mac.recording(story, .dark),
                iphone.recording(story, .light),
            ]
            #expect(Set(tests.map(\.test)).count == 3)
            #expect(tests.map(\.scope) == ["mac", "mac", "iphone"])
        }

        @Test func remembersPastResults() throws {
            let changed = ChangedSnapshots(project: try project(), device: .mac)
            #expect(changed.past() == nil)
            try FileManager.default.createDirectory(
                at: changed.buildDirectory, withIntermediateDirectories: true)
            let past = ChangedSnapshots.Past(
                settings: "s", outcomes: ["mac/light/M/G/S": Outcome(passed: true, reference: nil)])
            try changed.save(past)
            #expect(changed.past()?.outcomes == past.outcomes)
            #expect(changed.past()?.settings == "s")
        }
    }
#endif
