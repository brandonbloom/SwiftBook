#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore

    /// `swiftbook prune`: deletes references to stories that no longer exist.
    struct PruneCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Delete references to stories that no longer exist.",
            discussion: """
                Asks a renderer for every story, then deletes the reference directories under \
                Snapshots/ that match none of them. Only modules the renderer links are pruned, \
                so references for code it can't see are left alone. Variants of existing \
                stories are kept.
                """)

        @Flag(help: "List what would be deleted without deleting it.")
        var dryRun = false

        func run() throws {
            let project: Project
            let stories: [StoryInfo]
            do {
                project = try Project.current()
                let renderer = try Renderers.start(for: project)
                defer { renderer.shutdown() }
                stories = try renderer.stories()
            } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
            let orphans = Self.orphans(in: project.store, stories: stories)
            guard !orphans.isEmpty else {
                print("No references to prune.")
                return
            }
            for directory in orphans {
                print("\(dryRun ? "Would delete" : "Deleted") \(directory.path)")
                if !dryRun {
                    do { try FileManager.default.removeItem(at: directory) } catch {
                        warn("swiftbook: couldn't delete \(directory.path): \(error)")
                        throw Exit.broken.code
                    }
                }
            }
        }

        /// Story directories in `store` for modules that `stories` cover, but for none of the
        /// stories themselves.
        static func orphans(in store: SnapshotStore, stories: [StoryInfo]) -> [URL] {
            func key(_ url: URL) -> String { url.standardizedFileURL.path }
            let live = Set(
                stories.map {
                    key(
                        store.url(for: $0.id, device: .mac, environment: RenderEnvironment())
                            .deletingLastPathComponent())
                })
            let modules = Set(stories.map { SnapshotStore.fileName($0.module) })
            var orphans: [URL] = []
            let manager = FileManager.default
            func children(_ url: URL) -> [URL] {
                ((try? manager.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                    .filter {
                        (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    }
                    .sorted { $0.path < $1.path }
            }
            for module in children(store.root) where modules.contains(module.lastPathComponent) {
                for group in children(module) {
                    for story in children(group) where !live.contains(key(story)) {
                        orphans.append(story)
                    }
                }
            }
            return orphans
        }
    }
#endif
