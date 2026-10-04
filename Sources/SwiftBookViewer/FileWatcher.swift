#if os(macOS)
    import CoreServices
    import Foundation

    /// Watches a directory tree for changes to source files, through FSEvents.
    ///
    /// Build products, Git's internals, and reference images change as a result of building and
    /// testing, not editing, so changes under `.build`, `.swiftpm`, `.git`, and `Snapshots` are
    /// ignored.
    final class FileWatcher: @unchecked Sendable {
        // Unchecked: the stream is only touched on `queue`, and `onChange` is immutable.

        private let queue = DispatchQueue(label: "SwiftBook file watcher")
        private var stream: FSEventStreamRef?
        private let onChange: @Sendable ([String]) -> Void

        static let ignored = ["/.build/", "/.swiftpm/", "/.git/", "/Snapshots/"]

        /// Starts watching `directory`. `onChange` gets the changed paths that aren't ignored,
        /// batched by FSEvents over `latency`.
        init(
            directory: URL, latency: Duration = .milliseconds(200),
            onChange: @escaping @Sendable ([String]) -> Void
        ) {
            self.onChange = onChange
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil,
                release: nil, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, paths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
                let all = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                watcher.changed(Array(all.prefix(count)))
            }
            let seconds =
                Double(latency.components.seconds) + Double(latency.components.attoseconds) / 1e18
            stream = FSEventStreamCreate(
                nil, callback, &context, [directory.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), seconds,
                FSEventStreamCreateFlags(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
                        | kFSEventStreamCreateFlagNoDefer))
            if let stream {
                FSEventStreamSetDispatchQueue(stream, queue)
                FSEventStreamStart(stream)
            }
        }

        deinit {
            stop()
        }

        func stop() {
            queue.sync {
                guard let stream else { return }
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }

        /// Whether a change to `path` might need a rebuild.
        static func isRelevant(_ path: String) -> Bool {
            !ignored.contains { path.contains($0) } && !path.hasSuffix(".DS_Store")
        }

        private func changed(_ paths: [String]) {
            let relevant = paths.filter(Self.isRelevant)
            if !relevant.isEmpty { onChange(relevant) }
        }
    }
#endif
