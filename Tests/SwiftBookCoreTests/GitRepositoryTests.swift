#if os(macOS)
    import Foundation
    import Testing

    @testable import SwiftBookCore

    /// The Git service against scratch repositories.
    @Suite struct GitRepositoryTests {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "GitRepositoryTests-\(UUID())", directoryHint: .isDirectory)

        static let lfsInstalled = Shell.run(["git", "lfs", "version"])?.succeeded == true

        /// Runs git in the scratch repository, isolated from the user's configuration.
        @discardableResult
        func git(_ arguments: String...) throws -> String {
            let result = try #require(
                Shell.run(
                    [
                        "git", "-c", "user.name=Test", "-c", "user.email=test@example.com",
                        "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main",
                    ] + arguments,
                    in: directory,
                    environment: ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]))
            try #require(result.succeeded, "git \(arguments) failed: \(result.error)")
            return result.output
        }

        func write(_ text: String, to path: String) throws {
            let url = directory.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        func commit(_ message: String) throws {
            try git("add", "-A")
            try git("commit", "-q", "-m", message)
        }

        /// A repository with one commit on `main`.
        func repository() throws -> GitRepository {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try git("init", "-q")
            try write("one\n", to: "a.txt")
            try commit("first")
            let nested = directory.appending(path: "nested")
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            return try GitRepository(containing: nested)
        }

        @Test func findsTheTopLevelAndResolvesRevisions() throws {
            let repo = try repository()
            #expect(repo.relativePath(of: directory.appending(path: "x/y.png")) == "x/y.png")
            let head = try repo.resolve("HEAD")
            #expect(head.count == 40)
            #expect(try repo.revision(for: .head) == head)
            #expect(throws: GitError.self) { try repo.resolve("no-such-branch") }
        }

        @Test func failsOutsideARepository() throws {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            #expect(throws: GitError.self) { try GitRepository(containing: directory) }
        }

        @Test func readsFilesAtARevision() throws {
            let repo = try repository()
            let first = try repo.resolve("HEAD")
            try write("two\n", to: "a.txt")
            try commit("second")
            #expect(try repo.contents(of: "a.txt", at: first) == Data("one\n".utf8))
            #expect(try repo.contents(of: "a.txt", at: "HEAD") == Data("two\n".utf8))
            #expect(try repo.contents(of: "missing.txt", at: "HEAD") == nil)
            #expect(try repo.revision(for: .lastCommit) == first)
        }

        @Test func listsChangesIncludingStagedAndUntrackedFiles() throws {
            let repo = try repository()
            try write("gone\n", to: "Snapshots/old.png")
            try write("same\n", to: "Snapshots/kept.png")
            try commit("references")
            try write("changed\n", to: "a.txt")
            try FileManager.default.removeItem(at: directory.appending(path: "Snapshots/old.png"))
            try write("staged\n", to: "Snapshots/staged.png")
            try git("add", "Snapshots/staged.png")
            try write("untracked\n", to: "Snapshots/new png.png")
            let changes = try repo.changes(since: repo.revision(for: .head))
            #expect(
                changes == [
                    Change(path: "Snapshots/new png.png", kind: .added),
                    Change(path: "Snapshots/old.png", kind: .deleted),
                    Change(path: "Snapshots/staged.png", kind: .added),
                    Change(path: "a.txt", kind: .modified),
                ])
            #expect(
                try repo.changes(since: "HEAD", under: "Snapshots").map(\.path) == [
                    "Snapshots/new png.png", "Snapshots/old.png", "Snapshots/staged.png",
                ])
        }

        @Test func findsWhereTheBranchLeftMainAcrossARebase() throws {
            let repo = try repository()
            let fork = try repo.resolve("HEAD")
            try git("checkout", "-q", "-b", "feature")
            try write("feature\n", to: "b.txt")
            try commit("feature")
            #expect(try repo.revision(for: .branch(base: nil)) == fork)
            #expect(
                try repo.changes(since: repo.revision(for: .branch(base: nil))).map(\.path) == [
                    "b.txt"
                ])

            // Main moves on, and the branch is rebased onto it: the basis moves too.
            try git("checkout", "-q", "main")
            try write("main\n", to: "c.txt")
            try commit("main")
            let main = try repo.resolve("main")
            try git("checkout", "-q", "feature")
            try git("rebase", "-q", "main")
            #expect(try repo.revision(for: .branch(base: "main")) == main)
            #expect(
                try repo.changes(since: repo.revision(for: .branch(base: nil))).map(\.path) == [
                    "b.txt"
                ])
        }

        /// Sets up Git LFS for PNGs in the scratch repository.
        func trackPNGsInLFS() throws {
            try git("lfs", "install", "--local")
            try write("*.png filter=lfs diff=lfs merge=lfs -text\n", to: ".gitattributes")
        }

        @Test(.enabled(if: lfsInstalled)) func readsLFSFilesAsTheirContents() throws {
            let repo = try repository()
            try trackPNGsInLFS()
            try write("image one", to: "Snapshots/a.png")
            try commit("image")
            let first = try repo.resolve("HEAD")
            try write("image two", to: "Snapshots/a.png")
            try commit("image changed")
            // The committed blob is a pointer; reading it applies the LFS filter.
            #expect(
                try git("cat-file", "-p", "\(first):Snapshots/a.png").hasPrefix(
                    "version https://git-lfs"))
            #expect(try repo.contents(of: "Snapshots/a.png", at: first) == Data("image one".utf8))
            #expect(try repo.contents(of: "Snapshots/a.png", at: "HEAD") == Data("image two".utf8))
        }

        @Test(.enabled(if: lfsInstalled)) func explainsMissingLFSObjects() throws {
            let repo = try repository()
            try trackPNGsInLFS()
            try write("image", to: "Snapshots/a.png")
            try commit("image")
            // With no remote to fetch from, a deleted object can't come back.
            try FileManager.default.removeItem(at: directory.appending(path: ".git/lfs/objects"))
            #expect {
                try repo.contents(of: "Snapshots/a.png", at: "HEAD")
            } throws: { error in
                (error as? GitError)?.description.contains("Git LFS") == true
            }
        }
    }
#endif
