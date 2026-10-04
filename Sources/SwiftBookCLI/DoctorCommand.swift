#if os(macOS)
    import ArgumentParser
    import CoreGraphics
    import Foundation
    import SwiftBookCore

    /// `swiftbook doctor`: checks everything SwiftBook depends on.
    struct DoctorCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "doctor",
            abstract: "Check the toolchain, Git LFS, references, and capture permissions.",
            discussion: "Exits with status \(Exit.broken.rawValue) if any check fails.")

        @Flag(help: "Print the results as JSON.")
        var json = false

        func run() throws {
            let checks = Doctor.checks(project: try? Project.current())
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(["checks": checks]), as: UTF8.self))
            } else {
                for check in checks { print(check.formatted) }
            }
            if checks.contains(where: { $0.status == .failure }) { throw Exit.broken.code }
        }
    }

    /// One finding of `swiftbook doctor`.
    struct Check: Codable, Equatable {
        enum Status: String, Codable {
            case ok, warning, failure, skipped
        }

        var name: String
        var status: Status
        var detail: String
        /// What to do about a warning or failure.
        var fix: String?

        var formatted: String {
            let symbol =
                switch status {
                case .ok: "✓"
                case .warning: "!"
                case .failure: "✗"
                case .skipped: "-"
                }
            var line = "\(symbol) \(name): \(detail)"
            if let fix { line += "\n    \(fix)" }
            return line
        }
    }

    enum Doctor {
        /// Every check, for `project` if there is one.
        static func checks(project: Project?) -> [Check] {
            var checks = [macOS(), xcode(), git(), lfs()]
            if let project {
                checks += [lfsRule(project), references(project)]
            } else {
                checks.append(
                    Check(
                        name: "Project", status: .failure,
                        detail: "No Package.swift or .xcodeproj here or in a parent directory.",
                        fix: "Run swiftbook doctor in your package or project."))
            }
            checks += [capture(), simulators()]
            checks.append(
                Check(
                    name: "Discovery", status: .skipped,
                    detail:
                        "swift test checks it: a preview SwiftBook can't read fails loudly. swiftbook doctor will check it once the CLI runs renderers."
                ))
            return checks
        }

        static func macOS() -> Check {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let description = "\(version.majorVersion).\(version.minorVersion)"
            return version.majorVersion >= 27
                ? Check(name: "macOS", status: .ok, detail: description)
                : Check(
                    name: "macOS", status: .failure,
                    detail: "\(description); SwiftBook needs 27 or later.",
                    fix: "Update macOS.")
        }

        static func xcode() -> Check {
            guard let result = Shell.run(["xcodebuild", "-version"]), result.succeeded else {
                return Check(
                    name: "Xcode", status: .failure, detail: "xcodebuild isn't available.",
                    fix: "Install Xcode 27 and run: sudo xcode-select -s /Applications/Xcode.app")
            }
            let version = result.output.split(separator: "\n").map(String.init)
            let major = version.first.flatMap { $0.split(separator: " ").last }
                .flatMap { $0.split(separator: ".").first }.flatMap { Int($0) }
            let detail = version.joined(separator: ", ")
            guard let major, major >= 27 else {
                return Check(
                    name: "Xcode", status: .failure,
                    detail: "\(detail); SwiftBook needs 27 or later.",
                    fix: "Install Xcode 27 and select it with xcode-select.")
            }
            return Check(name: "Xcode", status: .ok, detail: detail)
        }

        static func git() -> Check {
            guard let result = Shell.run(["git", "--version"]), result.succeeded else {
                return Check(
                    name: "Git", status: .failure, detail: "git isn't available.",
                    fix: "Install Xcode's command line tools: xcode-select --install")
            }
            return Check(name: "Git", status: .ok, detail: result.output)
        }

        static func lfs() -> Check {
            guard let result = Shell.run(["git", "lfs", "version"]), result.succeeded else {
                return Check(
                    name: "Git LFS", status: .failure, detail: "git-lfs isn't installed.",
                    fix: "Install it (https://git-lfs.com), then run: git lfs install")
            }
            guard Shell.run(["git", "config", "filter.lfs.process"])?.succeeded == true else {
                return Check(
                    name: "Git LFS", status: .failure,
                    detail: "\(result.output), but its Git filters aren't set up.",
                    fix: "Run: git lfs install")
            }
            return Check(name: "Git LFS", status: .ok, detail: result.output)
        }

        static func lfsRule(_ project: Project) -> Check {
            switch project.referencesUseLFS {
            case true?:
                return Check(
                    name: "LFS rule", status: .ok,
                    detail: "References in \(project.store.root.path) go to Git LFS.")
            case false?:
                return Check(
                    name: "LFS rule", status: .warning,
                    detail: "References would be committed as ordinary Git files.",
                    fix: "Run: swiftbook init")
            case nil:
                return Check(
                    name: "LFS rule", status: .skipped,
                    detail: "\(project.root.path) isn't in a Git repository.")
            }
        }

        static func references(_ project: Project) -> Check {
            let (all, pointers) = project.references()
            guard pointers.isEmpty else {
                return Check(
                    name: "References", status: .failure,
                    detail:
                        "\(pointers.count) of \(all.count) are Git LFS pointers, not images, such as \(pointers[0].path).",
                    fix: "Run: git lfs pull")
            }
            return Check(
                name: "References", status: .ok,
                detail: all.isEmpty
                    ? "None yet. swift test records them."
                    : "\(all.count) in \(project.store.root.path).")
        }

        static func capture() -> Check {
            let method = try? CaptureMethod.current()
            if CGPreflightScreenCaptureAccess() {
                return Check(
                    name: "Capture", status: .ok,
                    detail:
                        "Screen Recording is allowed here, so macOS snapshots capture through the window server\(method == .emulated ? " (SWIFTBOOK_CAPTURE or a locked screen selects emulated capture now)" : "")."
                )
            }
            return Check(
                name: "Capture", status: .warning,
                detail:
                    "Screen Recording isn't allowed for this terminal, so macOS snapshots use emulated capture, which differs slightly from the screen.",
                fix:
                    "Allow your terminal in System Settings › Privacy & Security › Screen & System Audio Recording, or set SWIFTBOOK_CAPTURE=emulated to make the choice explicit."
            )
        }

        static func simulators() -> Check {
            guard let result = Shell.run(["xcrun", "simctl", "list", "runtimes"]), result.succeeded
            else {
                return Check(
                    name: "Simulators", status: .warning,
                    detail: "simctl isn't available, so iOS and tvOS snapshots won't be possible.",
                    fix: "Install Xcode 27.")
            }
            let missing = ["iOS", "tvOS"].filter { platform in
                !result.output.split(separator: "\n").contains {
                    $0.hasPrefix("\(platform) 27") || $0.hasPrefix("\(platform) 28")
                }
            }
            guard missing.isEmpty else {
                return Check(
                    name: "Simulators", status: .warning,
                    detail:
                        "No \(missing.joined(separator: " or ")) 27 simulator runtime. It's needed for those platforms' snapshots, once SwiftBook supports them.",
                    fix: "Install it in Xcode › Settings › Components.")
            }
            return Check(
                name: "Simulators", status: .ok, detail: "iOS and tvOS runtimes installed.")
        }
    }
#endif
