#if os(macOS)
    import ArgumentParser
    import Foundation
    import SwiftBookCore
    import Synchronization

    /// `swiftbook compress`: re-encodes existing references as compact PNGs.
    struct CompressCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compress",
            abstract: "Shrink existing references losslessly.",
            discussion: """
                Re-encodes every reference under Snapshots/ as compact a PNG as SwiftBook \
                records: the same pixels and metadata, in fewer bytes. Each file is checked to \
                decode to the same pixels with the same metadata before it's replaced. Nothing \
                is rendered. References recorded by SwiftBook 0.3 or later are already compact, \
                so this is a one-time migration, and safe to run again.
                """)

        @Flag(help: "Report what would shrink without changing any file.")
        var dryRun = false

        func run() throws {
            let store: SnapshotStore
            do { store = try Project.current().store } catch {
                warn("swiftbook: \(error)")
                throw Exit.broken.code
            }
            let (all, pointers) = store.references()
            let skipped = Set(pointers)
            let references = all.filter { !skipped.contains($0) }
            // Concurrently: a large project has hundreds of references, each a few MB decoded.
            let results = Mutex<[Result<SnapshotStore.Compaction, Error>]>([])
            DispatchQueue.concurrentPerform(iterations: references.count) { index in
                let result = Result { try store.compact(references[index], dryRun: dryRun) }
                results.withLock { $0.append(result) }
            }
            var (before, after, shrunk, failures) = (0, 0, 0, 0)
            for result in results.withLock({ $0 }) {
                switch result {
                case .success(let compaction):
                    before += compaction.before
                    after += compaction.after
                    if compaction.after < compaction.before { shrunk += 1 }
                case .failure(let error):
                    warn("swiftbook: \(error)")
                    failures += 1
                }
            }
            let verb = dryRun ? "Would compress" : "Compressed"
            print(
                "\(verb) \(shrunk) of \(references.count) references: \(Self.megabytes(before)) → \(Self.megabytes(after))."
            )
            if !pointers.isEmpty {
                warn(
                    "swiftbook: skipped \(pointers.count) references that are Git LFS pointers. Run git lfs pull, then compress again."
                )
            }
            if failures > 0 { throw Exit.broken.code }
        }

        static func megabytes(_ bytes: Int) -> String {
            (Double(bytes) / 1_000_000).formatted(.number.precision(.fractionLength(1))) + " MB"
        }
    }
#endif
