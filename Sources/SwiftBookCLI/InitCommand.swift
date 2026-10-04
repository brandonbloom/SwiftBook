#if os(macOS)
    import ArgumentParser
    import Foundation

    /// `swiftbook init`: sets a project up to store references in Git LFS.
    struct InitCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "init",
            abstract: "Store the project's reference images in Git LFS.",
            discussion: """
                Adds the LFS rule for Snapshots/ to the project's .gitattributes, unless one already \
                applies. Safe to run again.
                """)

        func run() throws {
            do {
                for line in try Self.setUp(try Project.current()) { print(line) }
            } catch let failure as Failure {
                warn("swiftbook: \(failure)")
                throw Exit.broken.code
            }
        }

        /// Sets up `project`, returning what it did and anything left for the user to do.
        static func setUp(_ project: Project) throws -> [String] {
            var report: [String] = []
            if project.referencesUseLFS == true {
                report.append("References already go to Git LFS.")
            } else {
                let attributes = project.root.appending(path: ".gitattributes")
                var contents = (try? String(contentsOf: attributes, encoding: .utf8)) ?? ""
                if !contents.isEmpty, !contents.hasSuffix("\n") { contents += "\n" }
                contents += "# Reference snapshots live in Git LFS.\n\(Project.lfsRule)\n"
                try contents.write(to: attributes, atomically: true, encoding: .utf8)
                report.append("Added the Git LFS rule for references to \(attributes.path).")
            }
            if project.repository == nil {
                report.append("Not in a Git repository yet; references will go to LFS once it is.")
            }
            switch Shell.run(["git", "lfs", "version"]) {
            case .some(let result) where result.succeeded:
                if Shell.run(["git", "config", "filter.lfs.process"], in: project.root)?.succeeded
                    != true
                {
                    report.append("Git LFS isn't set up for your account. Run: git lfs install")
                }
            default:
                report.append(
                    "Git LFS isn't installed. Install it (https://git-lfs.com), then run: git lfs install"
                )
            }
            return report
        }
    }
#endif
