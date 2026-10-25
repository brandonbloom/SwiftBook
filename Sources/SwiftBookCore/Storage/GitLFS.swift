import Foundation

/// Recognizes references that Git LFS hasn't downloaded.
///
/// In a clone or worktree where Git LFS isn't set up, or its objects weren't pulled, a
/// reference is a small text pointer rather than its image.
package enum GitLFS {
    /// How every pointer file begins.
    package static let pointerPrefix = Data("version https://git-lfs.github.com/spec/".utf8)

    /// Whether `data` is a pointer rather than the file it stands for.
    package static func isPointer(_ data: Data) -> Bool {
        data.starts(with: pointerPrefix)
    }

    /// The fix for references that are pointers.
    package static let fix = "git lfs pull (after git lfs install, if Git LFS isn't set up)"

    /// Why the reference at `path` can't be used.
    package static func pointerProblem(at path: String) -> String {
        "\(path) is a Git LFS pointer, not an image: its image wasn't downloaded. Run: \(fix)"
    }
}
