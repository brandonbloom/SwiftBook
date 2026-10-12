#if os(macOS)
    import Foundation
    import SwiftBookCore
    import Testing

    @testable import SwiftBookCLI

    /// The commands against scratch packages and Git repositories.
    @Suite struct CLITests {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "CLITests-\(UUID())", directoryHint: .isDirectory)

        /// A package, optionally in a Git repository of its own.
        func package(inRepository: Bool = true) throws -> Project {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try Data("// swift-tools-version: 6.2\n".utf8).write(
                to: directory.appending(path: "Package.swift"))
            if inRepository {
                #expect(Shell.run(["git", "init", "-q"], in: directory)?.succeeded == true)
            }
            return try Project(containing: directory.appending(path: "Sources"))
        }

        @Test func findsTheEnclosingProjectAndRepository() throws {
            let project = try package()
            #expect(project.root.standardizedFileURL.path == directory.standardizedFileURL.path)
            #expect(project.store.root.lastPathComponent == "Snapshots")
            #expect(project.repository != nil)
        }

        @Test func startsAnotherSimulatorOnlyWhenItPays() {
            // Fulbloom's iPhone run: 394 snapshots at about 0.34 s each.
            #expect(
                DeviceRun.worthStarting(remaining: 390, perItem: 0.34, renderers: 1, warm: false))
            // The zoo's: 72 at the same pace repays a booted simulator, not a cold one.
            #expect(DeviceRun.worthStarting(remaining: 68, perItem: 0.34, renderers: 1, warm: true))
            #expect(
                !DeviceRun.worthStarting(remaining: 68, perItem: 0.34, renderers: 1, warm: false))
            // A short tail isn't worth even a warm one.
            #expect(
                !DeviceRun.worthStarting(remaining: 20, perItem: 0.34, renderers: 2, warm: true))
        }

        @Test func failsOutsideAProject() {
            #expect(throws: Failure.self) {
                try Project(containing: URL(filePath: "/", directoryHint: .isDirectory))
            }
        }

        @Test func initAddsTheLFSRuleOnce() throws {
            let project = try package()
            #expect(project.referencesUseLFS == false)
            let first = try InitCommand.setUp(project)
            #expect(first.contains { $0.hasPrefix("Added the Git LFS rule") })
            #expect(project.referencesUseLFS == true)

            let second = try InitCommand.setUp(project)
            #expect(second.contains("References already go to Git LFS."))
            let attributes = try String(
                contentsOf: directory.appending(path: ".gitattributes"), encoding: .utf8)
            #expect(attributes.components(separatedBy: Project.lfsRule).count == 2)
        }

        @Test func initKeepsExistingAttributes() throws {
            let project = try package()
            try Data("*.pbxproj merge=union".utf8).write(
                to: directory.appending(path: ".gitattributes"))
            _ = try InitCommand.setUp(project)
            let attributes = try String(
                contentsOf: directory.appending(path: ".gitattributes"), encoding: .utf8)
            #expect(attributes.hasPrefix("*.pbxproj merge=union\n# Reference snapshots"))
        }

        @Test func initWorksOutsideARepository() throws {
            let project = try package(inRepository: false)
            let report = try InitCommand.setUp(project)
            #expect(report.contains { $0.hasPrefix("Not in a Git repository") })
            #expect(Doctor.lfsRule(project).status == .skipped)
        }

        @Test func doctorFindsReferencesThatAreLFSPointers() throws {
            let project = try package()
            #expect(Doctor.references(project).status == .ok)
            let story = project.store.root.appending(path: "Module/Group/Story")
            try FileManager.default.createDirectory(at: story, withIntermediateDirectories: true)
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: story.appending(path: "mac.light.png"))
            try Data("version https://git-lfs.github.com/spec/v1\noid sha256:0\nsize 1\n".utf8)
                .write(to: story.appending(path: "mac.dark.png"))
            let check = Doctor.references(project)
            #expect(check.status == .failure)
            #expect(check.detail.hasPrefix("1 of 2 are Git LFS pointers"))
            #expect(check.fix == "Run: git lfs pull")
            // swiftbook test stops before rendering anything.
            #expect(
                TestCommand.lfsProblem(project)?.hasPrefix(
                    "1 of 2 references are Git LFS pointers") == true)
        }

        @Test func doctorAsksForTheLFSRule() throws {
            let project = try package()
            #expect(Doctor.lfsRule(project).status == .warning)
            _ = try InitCommand.setUp(project)
            #expect(Doctor.lfsRule(project).status == .ok)
        }

        @Test func doctorFailsWithoutAProject() {
            let checks = Doctor.checks(project: nil)
            #expect(checks.contains { $0.name == "Project" && $0.status == .failure })
        }

        @Test func parsesEachCommand() throws {
            #expect(try SwiftBookCommand.parseAsRoot(["init"]) is InitCommand)
            #expect(
                try (SwiftBookCommand.parseAsRoot(["doctor", "--json"]) as? DoctorCommand)?.json
                    == true
            )
            #expect(
                try (SwiftBookCommand.parseAsRoot(["review", "--print"]) as? ReviewCommand)?.print
                    == true)
            #expect(SwiftBookCommand.exitCode(for: Exit.changed.code).rawValue == 1)
        }
    }
#endif
