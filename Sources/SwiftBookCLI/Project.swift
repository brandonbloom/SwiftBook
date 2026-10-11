#if os(macOS)
    import Foundation
    import SwiftBookCore

    /// The package or Xcode project SwiftBook works on, and the Git repository around it.
    struct Project {
        /// The directory with `Package.swift` or the `.xcodeproj`.
        let root: URL
        let store: SnapshotStore
        /// The repository the project is in, if any.
        let repository: GitRepository?

        /// The project enclosing `directory`.
        init(containing directory: URL) throws {
            do {
                // The store finds the project from a file in it.
                store = try SnapshotStore.forProject(
                    containing: directory.appending(path: "_").path)
            } catch {
                throw Failure(
                    description:
                        "No Package.swift or .xcodeproj in \(directory.path) or its parents. Run swiftbook in a package or Xcode project."
                )
            }
            root = store.root.deletingLastPathComponent()
            repository = try? GitRepository(containing: root)
        }

        /// The project enclosing the current directory.
        static func current() throws -> Project {
            try Project(
                containing: URL(
                    filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
            )
        }

        /// The `.gitattributes` rule that stores references in Git LFS.
        static let lfsRule = "**/Snapshots/**/*.png filter=lfs diff=lfs merge=lfs -text"

        /// Whether Git would store a reference in LFS, or `nil` if there's no repository.
        var referencesUseLFS: Bool? {
            guard repository != nil else { return nil }
            // Any path under Snapshots will do: attributes apply by pattern, not by existence.
            let probe = store.root.appending(path: "Module/Group/Story/mac.light.png")
            guard
                let result = Shell.run(
                    ["git", "check-attr", "filter", "--", probe.path], in: root),
                result.succeeded
            else { return nil }
            return result.output.hasSuffix(": filter: lfs")
        }

        /// Every reference PNG, and those that are Git LFS pointers whose images aren't downloaded.
        func references() -> (all: [URL], pointers: [URL]) {
            store.references()
        }
    }
#endif
