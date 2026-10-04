#if os(macOS)
    import Foundation
    import SwiftBookCore

    /// What the viewer compares stories against.
    enum ViewerBasis: Hashable, Sendable {
        /// The last commit: uncommitted changes.
        case uncommitted
        /// The commit before the last: what the last commit changed.
        case lastCommit
        /// Where this branch left the default branch.
        case branch
        /// Any revision Git understands.
        case revision(String)

        var title: String {
            switch self {
            case .uncommitted: "Uncommitted changes"
            case .lastCommit: "Last commit"
            case .branch: "This branch"
            case .revision(let revision): revision
            }
        }

        var gitBasis: Basis {
            switch self {
            case .uncommitted: .head
            case .lastCommit: .lastCommit
            case .branch: .branch(base: nil)
            case .revision(let revision): .revision(revision)
            }
        }
    }

    /// How a story differs from the basis.
    enum ChangeStatus: Hashable, Sendable {
        /// Not known yet.
        case pending
        /// Its source file changed; whether its image did isn't known yet.
        case sourceChanged
        case unchanged
        case changed
        /// It has no reference at the basis.
        case new
        /// It didn't render.
        case failed

        /// Whether the story belongs under a "changed only" filter.
        var isChange: Bool {
            switch self {
            case .sourceChanged, .changed, .new, .failed: true
            case .pending, .unchanged: false
            }
        }
    }

    /// What the viewer needs from a package's Git history. Calls block, so the model makes them
    /// off the main thread.
    protocol HistorySource: Sendable {
        /// The basis to start with.
        func defaultBasis() -> ViewerBasis
        /// The commit `basis` names, and the files that differ from it in the working tree.
        func changes(against basis: ViewerBasis) throws -> (revision: String, paths: [String])
        /// The Mac reference for `story` in `appearance` as of `revision`, or `nil` if there
        /// was none.
        func reference(
            for story: StoryID, appearance: RenderEnvironment.Appearance, at revision: String
        ) throws -> Data?
    }

    /// A package's Git history.
    struct History: HistorySource {
        let repository: GitRepository
        let store: SnapshotStore

        init(package: URL) throws {
            repository = try GitRepository(containing: package)
            store = SnapshotStore(
                root: package.appending(path: "Snapshots", directoryHint: .isDirectory))
        }

        /// Uncommitted changes if there are any, else the last commit.
        func defaultBasis() -> ViewerBasis {
            let head = try? repository.revision(for: .head)
            let dirty =
                head.flatMap { try? repository.changes(since: $0) }.map { !$0.isEmpty } ?? false
            return dirty ? .uncommitted : .lastCommit
        }

        func changes(against basis: ViewerBasis) throws -> (revision: String, paths: [String]) {
            let revision = try repository.revision(for: basis.gitBasis)
            return (revision, try repository.changes(since: revision).map(\.path))
        }

        func reference(
            for story: StoryID, appearance: RenderEnvironment.Appearance, at revision: String
        ) throws -> Data? {
            var environment = RenderEnvironment()
            environment.appearance = appearance
            let url = store.url(for: story, device: .mac, environment: environment)
            guard let path = repository.relativePath(of: url) else { return nil }
            return try repository.contents(of: path, at: revision)
        }

        /// Whether `story`'s source file is among `paths`, relative to the repository. A story
        /// knows its file only as `Module/File.swift`, so this matches the file's name inside a
        /// directory named for the module.
        static func sourceChanged(_ story: StoryInfo, in paths: [String]) -> Bool {
            guard let fileID = story.fileID, let file = fileID.split(separator: "/").last else {
                return false
            }
            return paths.contains { path in
                let components = path.split(separator: "/")
                return components.last == file
                    && components.dropLast().contains(Substring(story.module))
            }
        }

        /// How `render` compares with `reference`, the PNG at the basis.
        static func imageStatus(render: Data, reference: Data?) -> ChangeStatus {
            guard let reference else { return .new }
            guard
                let expected = try? SnapshotStore.image(reference, at: "reference"),
                let actual = try? SnapshotStore.image(render, at: "render"),
                let diff = try? ImageDiff.compare(expected: expected, actual: actual)
            else { return .changed }
            return diff.matches ? .unchanged : .changed
        }
    }
#endif
