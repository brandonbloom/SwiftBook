#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook diff`: summarizes how references changed against a revision.
    struct DiffCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "diff",
            abstract: "Summarize how references changed against a revision.",
            discussion: """
                Compares the references in the working tree, including staged and untracked \
                ones, with those at the revision. Exits with status \(Exit.changed.rawValue) if \
                any reference was added, deleted, or changed beyond tolerance.
                """)

        enum Format: String, ExpressibleByArgument, CaseIterable {
            case human, json, junit
        }

        @Argument(help: "The revision to compare against.")
        var revision = "HEAD"

        @Flag(help: "Compare against where HEAD left the revision, like git diff --merge-base.")
        var mergeBase = false

        @Option(
            help:
                "How to print the changes: \(Format.allCases.map(\.rawValue).joined(separator: ", "))."
        )
        var format = Format.human

        @Flag(help: "Write a page of the changes, with before, after and diff images, and open it.")
        var open = false

        @Option(
            help: ArgumentHelp(
                "Write the page of changes to this file, with its images inside it.",
                discussion: "One file, to send to someone or open on a phone.",
                valueName: "file"))
        var export: String?

        func run() throws {
            let project: Project
            let repository: GitRepository
            let basis: String
            let changes: [ReferenceChange]
            do {
                project = try Project.current()
                guard let found = project.repository else {
                    throw Failure(description: "\(project.root.path) isn't in a Git repository.")
                }
                repository = found
                basis =
                    try mergeBase ? repository.mergeBase(revision) : repository.resolve(revision)
                changes = try project.store.changes(since: basis, in: repository)
            } catch let failure as Failure {
                warn("swiftbook: \(failure)")
                throw Exit.broken.code
            } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
            let label = "\(mergeBase ? "merge base with " : "")\(revision) (\(basis.prefix(9)))"
            switch format {
            case .human: print(Self.human(changes, against: label))
            case .json: print(try Self.json(changes, revision: revision, commit: basis))
            case .junit: print(Self.junit(changes, against: label))
            }
            if open || export != nil {
                do {
                    let page = try Self.writePage(
                        changes, project: project, against: label,
                        export: export.map { URL(filePath: $0) })
                    if open, Shell.run(["open", page.path])?.succeeded != true {
                        warn("swiftbook: couldn't open \(page.path)")
                    }
                } catch {
                    warn("swiftbook: couldn't write the page of changes: \(error)")
                    throw Exit.broken.code
                }
            }
            if changes.contains(where: \.isSignificant) { throw Exit.changed.code }
        }

        // MARK: Output

        static func summary(of change: ReferenceChange) -> String {
            guard let diff = change.diff else { return "" }
            guard diff.sizesMatch else {
                return
                    "size \(Int(diff.expectedSize.width))×\(Int(diff.expectedSize.height)) → \(Int(diff.actualSize.width))×\(Int(diff.actualSize.height))"
            }
            guard !diff.matches else { return "within tolerance" }
            let percent = (diff.changedPixelRatio * 100).formatted(
                .number.precision(.fractionLength(0...2)))
            return
                "\(diff.changedPixels) pixels (\(percent)%), max ΔE \(Int(diff.maxDeltaE.rounded()))"
        }

        static func human(_ changes: [ReferenceChange], against label: String) -> String {
            guard !changes.isEmpty else { return "No references changed against \(label)." }
            let count = changes.count == 1 ? "1 reference" : "\(changes.count) references"
            var lines = ["\(count) changed against \(label):"]
            let width = changes.map(\.story.count).max() ?? 0
            for change in changes {
                let story = change.story.padding(toLength: width, withPad: " ", startingAt: 0)
                let kind = change.kind.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)
                lines.append(
                    "  \(kind)  \(story)  \(change.variant)  \(summary(of: change))"
                        .replacing(/\s+$/, with: ""))
            }
            return lines.joined(separator: "\n")
        }

        struct JSONChange: Encodable {
            var path: String
            var story: String
            var variant: String
            var kind: ReferenceChange.Kind
            var significant: Bool
            var changedPixels: Int?
            var changedPixelRatio: Double?
            var maxDeltaE: Double?
            var sizeChanged: Bool?
        }

        struct JSONReport: Encodable {
            var revision: String
            var commit: String
            var changes: [JSONChange]
        }

        static func json(_ changes: [ReferenceChange], revision: String, commit: String) throws
            -> String
        {
            let report = JSONReport(
                revision: revision, commit: commit,
                changes: changes.map { change in
                    JSONChange(
                        path: change.path, story: change.story, variant: change.variant,
                        kind: change.kind, significant: change.isSignificant,
                        changedPixels: change.diff?.changedPixels,
                        changedPixelRatio: change.diff?.changedPixelRatio,
                        // Infinity, for a size change, isn't valid JSON.
                        maxDeltaE: change.diff.flatMap { $0.sizesMatch ? $0.maxDeltaE : nil },
                        sizeChanged: change.diff.map { !$0.sizesMatch })
                })
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            return String(decoding: try encoder.encode(report), as: UTF8.self)
        }

        /// One test case per changed reference, failing if the change is significant.
        static func junit(_ changes: [ReferenceChange], against label: String) -> String {
            func escape(_ text: String) -> String {
                text.replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: "\"", with: "&quot;")
            }
            let failures = changes.filter(\.isSignificant).count
            var lines = [
                #"<?xml version="1.0" encoding="UTF-8"?>"#,
                #"<testsuites name="swiftbook diff" tests="\#(changes.count)" failures="\#(failures)">"#,
                #"<testsuite name="References changed against \#(escape(label))" tests="\#(changes.count)" failures="\#(failures)">"#,
            ]
            for change in changes {
                let name = "\(change.story) (\(change.variant))"
                let open =
                    #"<testcase classname="\#(escape(change.story))" name="\#(escape(name))""#
                if change.isSignificant {
                    let message = "\(change.kind.rawValue) \(summary(of: change))"
                        .trimmingCharacters(in: .whitespaces)
                    lines.append(
                        #"\#(open)><failure message="\#(escape(message))">\#(escape(change.path))</failure></testcase>"#
                    )
                } else {
                    lines.append("\(open)/>")
                }
            }
            lines += ["</testsuite>", "</testsuites>"]
            return lines.joined(separator: "\n")
        }

        /// Writes a review page of `changes` under the project's `.build/swiftbook/diff`, and
        /// returns it. With `export`, also writes a copy holding its images to that file.
        static func writePage(
            _ changes: [ReferenceChange], project: Project, against label: String,
            export: URL? = nil
        ) throws -> URL {
            let base = project.root.appending(path: ".build/swiftbook/diff")
            try? FileManager.default.removeItem(at: base)
            var entries: [ReviewEntry] = []
            for change in changes {
                let stem = base.appending(path: "images").appending(path: change.story)
                    .appending(path: change.variant)
                try FileManager.default.createDirectory(
                    at: stem.deletingLastPathComponent(), withIntermediateDirectories: true)
                var images: [ReviewEntry.Image] = []
                func save(_ data: Data?, as role: String) throws {
                    guard let data else { return }
                    let url = stem.appendingPathExtension("\(role).png")
                    try data.write(to: url)
                    images.append(.init(role: role, path: url.path))
                }
                try save(change.previous, as: "before")
                try save(change.current, as: "after")
                try save(try change.diff?.pngData(), as: "diff")
                let kind: ReviewEntry.Kind =
                    switch change.kind {
                    case .added: .new
                    case .modified: .changed
                    case .deleted: .deleted
                    }
                entries.append(
                    ReviewEntry(
                        story: change.story, variant: change.variant, kind: kind,
                        message: "\(change.kind.rawValue) \(summary(of: change))"
                            .trimmingCharacters(in: .whitespaces),
                        images: images, region: change.diff?.changedRegion))
            }
            let page = base.appending(path: "index.html")
            try ReviewPage.write(entries, to: page, subtitle: "Against \(label)")
            if let export {
                try ReviewPage.write(
                    entries, to: export, subtitle: "Against \(label)", inlineImages: true)
            }
            return page
        }
    }
#endif
