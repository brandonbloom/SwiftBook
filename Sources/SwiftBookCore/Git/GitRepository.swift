#if os(macOS)
    import Foundation

    /// A Git error, with what Git said.
    package struct GitError: Error, CustomStringConvertible, Sendable {
        package let description: String
    }

    /// The revision to compare the working tree against.
    package enum Basis: Hashable, Sendable {
        /// The last commit: uncommitted changes.
        case head
        /// The commit before the last: the last commit and uncommitted changes.
        case lastCommit
        /// Where the current branch left `base`, or the default branch if `nil`: everything on
        /// the branch.
        case branch(base: String?)
        /// Any revision Git understands.
        case revision(String)
    }

    /// A file that differs between a revision and the working tree.
    package struct Change: Hashable, Sendable {
        package enum Kind: Hashable, Sendable {
            case added, modified, deleted
        }

        /// The path relative to the repository's top level.
        package let path: String
        package let kind: Kind
    }

    /// A Git repository, read through the `git` command.
    ///
    /// Paths are relative to the repository's top level. Renames appear as a deletion and an
    /// addition.
    package struct GitRepository: Sendable {
        /// The top level of the working tree.
        package let root: URL

        /// The repository containing `directory`.
        package init(containing directory: URL) throws {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { throw GitError(description: "\(directory.path) isn't a directory") }
            let result = try Self.git(["rev-parse", "--show-toplevel"], in: directory)
            root = URL(filePath: result.output, directoryHint: .isDirectory)
        }

        /// The full commit hash `revision` names.
        package func resolve(_ revision: String) throws -> String {
            try git(["rev-parse", "--verify", "--end-of-options", "\(revision)^{commit}"]).output
        }

        /// The best common ancestor of two commits.
        package func mergeBase(_ revision: String, _ other: String = "HEAD") throws -> String {
            try git(["merge-base", "--end-of-options", revision, other]).output
        }

        /// The branch others branch from: the remote's default branch if known, else a local
        /// `main` or `master`.
        package func defaultBranch() throws -> String {
            if let result = try? git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"]) {
                return result.output
            }
            for candidate in ["main", "master"] where (try? resolve(candidate)) != nil {
                return candidate
            }
            throw GitError(
                description:
                    "can't tell the default branch: there's no origin/HEAD, main, or master in \(root.path)"
            )
        }

        /// The commit `basis` compares against.
        package func revision(for basis: Basis) throws -> String {
            switch basis {
            case .head: try resolve("HEAD")
            case .lastCommit: try resolve("HEAD~1")
            case .branch(let base): try mergeBase(base ?? defaultBranch())
            case .revision(let revision): try resolve(revision)
            }
        }

        /// The file at `path` as of `revision`, or `nil` if it didn't exist then.
        ///
        /// Git's filters apply, so a Git LFS file comes back as its image, downloaded if this
        /// clone doesn't have it.
        package func contents(of path: String, at revision: String) throws -> Data? {
            let object = "\(revision):\(path)"
            guard (try? git(["cat-file", "-e", object])) != nil else { return nil }
            let data: Data
            do {
                data = try git(["cat-file", "--filters", object]).data
            } catch let error as GitError {
                throw GitError(
                    description:
                        "can't read \(path) as of \(revision); if it's in Git LFS, check that its object was pushed: \(error.description)"
                )
            }
            if GitLFS.isPointer(data) {
                throw GitError(
                    description:
                        "\(path) as of \(revision) is a Git LFS pointer; install Git LFS and run: git lfs install"
                )
            }
            return data
        }

        /// The files that differ between `revision` and the working tree, including staged and
        /// untracked files, under `directory` if given.
        package func changes(since revision: String, under directory: String? = nil) throws
            -> [Change]
        {
            let pathspec = ["--", directory ?? "."]
            let diff = try git(
                ["diff", "--name-status", "--no-renames", "-z", "--end-of-options", revision]
                    + pathspec)
            var changes: [Change] = []
            var fields = Self.split(diff.data)[...]
            while let status = fields.popFirst(), let path = fields.popFirst() {
                let kind: Change.Kind
                switch status.first {
                case "A": kind = .added
                case "D": kind = .deleted
                default: kind = .modified
                }
                changes.append(Change(path: path, kind: kind))
            }
            let untracked = try git(
                ["ls-files", "--others", "--exclude-standard", "-z"] + pathspec)
            changes += Self.split(untracked.data).map { Change(path: $0, kind: .added) }
            return changes.sorted { $0.path < $1.path }
        }

        /// `url`'s path relative to the top level, or `nil` if it's outside the working tree.
        package func relativePath(of url: URL) -> String? {
            let file = url.standardizedFileURL.resolvingSymlinksInPath().path
            let top = root.standardizedFileURL.resolvingSymlinksInPath().path
            guard file.hasPrefix(top + "/") else { return nil }
            return String(file.dropFirst(top.count + 1))
        }

        // MARK: Running Git

        private func git(_ arguments: [String]) throws -> Shell.Result {
            try Self.git(arguments, in: root)
        }

        private static func git(_ arguments: [String], in directory: URL) throws -> Shell.Result {
            // Paths come back verbatim, not quoted, and Git never stops to ask for credentials.
            guard
                let result = Shell.run(
                    ["git", "-c", "core.quotePath=false"] + arguments, in: directory,
                    environment: ["GIT_TERMINAL_PROMPT": "0"])
            else { throw GitError(description: "git isn't available") }
            guard result.succeeded else {
                throw GitError(
                    description:
                        "git \(arguments.joined(separator: " ")) failed: \(result.error.isEmpty ? "exit \(result.status)" : result.error)"
                )
            }
            return result
        }

        /// NUL-separated fields.
        private static func split(_ data: Data) -> [String] {
            data.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        }
    }
#endif
