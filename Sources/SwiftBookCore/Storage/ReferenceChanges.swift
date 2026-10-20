#if os(macOS)
    import CoreGraphics
    import Foundation
    import ImageIO

    /// A reference that differs between a revision and the working tree.
    public struct ReferenceChange: Sendable {
        public enum Kind: String, Sendable, Codable {
            case added, modified, deleted
            /// Modified, but only in its encoding: the image decodes to the same pixels, with
            /// the same metadata, as by `swiftbook compress`.
            case reencoded
        }

        /// The path relative to the repository's top level.
        public let path: String
        /// The story, as `Module/Group/Name`, from the reference's place in `Snapshots/`.
        public let story: String
        /// The variant, such as `mac.light`.
        public let variant: String
        public let kind: Kind
        /// For a modified reference, how its image changed.
        public let diff: ImageDiff?
        /// The reference as of the revision, for a modified or deleted reference.
        public let previous: Data?
        /// The reference in the working tree, for an added or modified reference.
        public let current: Data?

        /// Whether the change matters: anything but a modified reference whose image is within
        /// tolerance of the old one.
        public var isSignificant: Bool { diff.map { !$0.matches } ?? true }
    }

    extension SnapshotStore {
        /// The references that differ between `revision` and the working tree.
        public func changes(since revision: String, in repository: GitRepository) throws
            -> [ReferenceChange]
        {
            guard let directory = repository.relativePath(of: root) else {
                throw StorageError(
                    description: "\(root.path) isn't in the repository at \(repository.root.path)")
            }
            return try repository.changes(since: revision, under: directory)
                .filter { $0.path.hasSuffix(".png") }
                .map { change in
                    let file = repository.root.appending(path: change.path)
                    // Snapshots/<Module>/<Group>/<Story>/<variant>.png
                    let components = change.path.dropFirst(directory.count + 1)
                        .split(separator: "/").map(String.init)
                    let story = components.dropLast().joined(separator: "/")
                    let variant = String(components.last?.dropLast(".png".count) ?? "")
                    switch change.kind {
                    case .added:
                        return ReferenceChange(
                            path: change.path, story: story, variant: variant, kind: .added,
                            diff: nil, previous: nil, current: try Data(contentsOf: file))
                    case .deleted:
                        return ReferenceChange(
                            path: change.path, story: story, variant: variant, kind: .deleted,
                            diff: nil,
                            previous: try repository.contents(of: change.path, at: revision),
                            current: nil)
                    case .modified:
                        let previous = try repository.contents(of: change.path, at: revision)
                        let current = try Data(contentsOf: file)
                        let diff = try ImageDiff.compare(
                            expected: Self.image(previous ?? Data(), at: change.path),
                            actual: Self.image(current, at: change.path))
                        let reencoded =
                            diff.isIdentical
                            && (try? PNG.text(in: previous ?? Data()))
                                == (try? PNG.text(in: current))
                        return ReferenceChange(
                            path: change.path, story: story, variant: variant,
                            kind: reencoded ? .reencoded : .modified,
                            diff: diff, previous: previous, current: current)
                    }
                }
        }
    }
#endif
