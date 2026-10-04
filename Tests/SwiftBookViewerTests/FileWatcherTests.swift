#if os(macOS)
    import Foundation
    import Testing

    @testable import SwiftBookViewer

    @Suite struct FileWatcherTests {
        @Test func reportsSourceChangesButNotBuildProducts() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(
                path: "FileWatcherTests-\(UUID())", directoryHint: .isDirectory)
            for path in ["Sources", ".build", "Snapshots/M"] {
                try FileManager.default.createDirectory(
                    at: directory.appending(path: path), withIntermediateDirectories: true)
            }
            let (changes, continuation) = AsyncStream.makeStream(of: [String].self)
            let watcher = FileWatcher(directory: directory, latency: .milliseconds(50)) {
                continuation.yield($0)
            }
            defer { watcher.stop() }
            // FSEvents needs a moment before it reports anything.
            try await Task.sleep(for: .milliseconds(500))
            try Data("ignored".utf8).write(to: directory.appending(path: ".build/output.o"))
            try Data("ignored".utf8).write(
                to: directory.appending(path: "Snapshots/M/mac.light.png"))
            try Data("struct A {}".utf8).write(to: directory.appending(path: "Sources/A.swift"))

            // Collect batches until the edit shows up, or give up after a few seconds.
            let timeout = Task {
                try await Task.sleep(for: .seconds(5))
                continuation.finish()
            }
            defer { timeout.cancel() }
            var sawEdit = false
            for await batch in changes {
                #expect(
                    batch.allSatisfy { !$0.contains("/.build/") && !$0.contains("/Snapshots/") })
                if batch.contains(where: { $0.hasSuffix("/Sources/A.swift") }) {
                    sawEdit = true
                    break
                }
            }
            #expect(sawEdit)
        }

        @Test(arguments: [
            ("/p/Sources/A.swift", true), ("/p/Package.swift", true),
            ("/p/.build/debug/x.o", false), ("/p/.git/index", false),
            ("/p/Snapshots/M/G/S/mac.light.png", false), ("/p/Sources/.DS_Store", false),
        ])
        func filtersPaths(path: String, relevant: Bool) {
            #expect(FileWatcher.isRelevant(path) == relevant)
        }
    }
#endif
