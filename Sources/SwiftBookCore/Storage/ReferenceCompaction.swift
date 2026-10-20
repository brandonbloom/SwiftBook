import Foundation

extension SnapshotStore {
    /// The outcome of compacting one reference.
    public struct Compaction: Sendable {
        public let url: URL
        /// The file's size before and after, the same if it was already compact.
        public let before: Int
        public let after: Int
    }

    /// Re-encodes the reference at `url` as a compact PNG, unless `dryRun`, if that's smaller.
    ///
    /// Before replacing the file, this checks that the new encoding decodes to the same pixels
    /// and carries the same metadata, and throws if it doesn't, leaving the file as it was.
    public func compact(_ url: URL, dryRun: Bool = false) throws -> Compaction {
        let original = try Data(contentsOf: url)
        if GitLFS.isPointer(original) {
            throw StorageError(description: GitLFS.pointerProblem(at: url.path))
        }
        let compact = try PNG.compact(original)
        guard compact.count < original.count else {
            return Compaction(url: url, before: original.count, after: original.count)
        }
        let (old, new) = try (
            Bitmap(Self.image(original, at: url.path)).pixels,
            Bitmap(Self.image(compact, at: url.path)).pixels
        )
        // memcmp: comparing arrays element by element is slow in debug builds.
        let samePixels =
            old.count == new.count
            && old.withUnsafeBytes { old in
                new.withUnsafeBytes { memcmp(old.baseAddress, $0.baseAddress, old.count) == 0 }
            }
        guard samePixels, try PNG.text(in: compact) == PNG.text(in: original) else {
            throw StorageError(
                description: "\(url.path) didn't re-encode losslessly, so it was left as it was")
        }
        if !dryRun { try compact.write(to: url, options: .atomic) }
        return Compaction(url: url, before: original.count, after: compact.count)
    }
}
