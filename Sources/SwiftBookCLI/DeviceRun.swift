#if os(macOS)
    import Foundation
    import SwiftBookCore

    /// One `swiftbook test` pass over a device, spread across as many renderers as are worth
    /// starting: renderer processes on the Mac, and pooled simulators, as are free, for the
    /// others.
    ///
    /// The run starts one renderer, leasing a simulator and waiting for one if it must, and lists
    /// the stories. Every story and appearance goes into one queue, which each renderer works
    /// through. Meanwhile it starts more renderers, without ever waiting for a simulator, while
    /// enough work remains to repay starting them: a Mac renderer process costs a second or two,
    /// a booted simulator a few seconds, and a cold one about 15 more.
    final class DeviceRun: @unchecked Sendable {
        // Unchecked: `lock` guards the mutable state; the rest is immutable.

        typealias Item = (story: StoryID, appearance: RenderEnvironment.Appearance)

        let project: Project
        let device: Device
        let mode: RecordMode
        let tolerance: ImageDiff.Tolerance
        /// The most renderers this run may use: processes on the Mac, simulators otherwise.
        let jobs: Int

        private let lock = NSLock()
        private var items: [Item] = []
        private var next = 0
        private var finished = 0
        private var started = ContinuousClock.now
        private var renderers: [RestartingRenderer] = []
        /// Results by their item's place in the queue.
        private var results: [(index: Int, result: TestCommand.Result)] = []
        private var app: RendererHost.App?
        /// The Mac renderer's executable.
        private var executable: URL?
        private var counts = (matched: 0, new: 0, rerecorded: 0, failed: 0, glassNoise: 0)
        private var failed = false

        /// Roughly how long starting a renderer takes: a process on the Mac, and an app in a
        /// booted simulator and in a cold one.
        static let macStart = 2.0
        static let warmStart = 5.0
        static let coldStart = 20.0

        init(
            project: Project, device: Device, mode: RecordMode, tolerance: ImageDiff.Tolerance,
            jobs: Int
        ) {
            self.project = project
            self.device = device
            self.mode = mode
            self.tolerance = tolerance
            self.jobs = max(jobs, 1)
        }

        func run() throws -> (results: [TestCommand.Result], failed: Bool) {
            let first: RestartingRenderer
            if device == .mac {
                Renderers.progress("Building the renderer…")
                let executable = try RendererHost(package: project.root).build()
                lock.withLock { self.executable = executable }
                first = try Self.macRenderer(executable)
            } else {
                let app = try Renderers.buildApp(for: project, on: device)
                lock.withLock { self.app = app }
                Renderers.progress("Starting the simulator…")
                first = try Renderers.start(
                    app,
                    in: SimulatorPool.lease(
                        for: device, waiting: Renderers.progress,
                        keepWarm: SimulatorIdleCommand.start))
            }
            let stories = try first.stories().filter(\.isTested)
            lock.withLock {
                items = stories.flatMap { story in
                    RenderEnvironment.Appearance.allCases.map { (story.id, $0) }
                }
                renderers = [first]
                started = .now
            }

            let workers = DispatchGroup()
            work(with: first, in: workers)
            // Start more renderers while it pays; stop once the queue is drained.
            while jobs > 1, !isDrained {
                if lock.withLock({ renderers.count }) < jobs, let renderer = recruit() {
                    lock.withLock { renderers.append(renderer) }
                    work(with: renderer, in: workers)
                } else {
                    Thread.sleep(forTimeInterval: 1)
                }
            }
            workers.wait()

            let renderers = lock.withLock { self.renderers }
            for renderer in renderers { renderer.shutdown() }
            let restarts = renderers.reduce(0) { $0 + $1.restarts }
            let incidents = renderers.flatMap(\.incidents)
            return lock.withLock {
                let glass =
                    counts.glassNoise > 0 ? " (\(counts.glassNoise) ignoring glass noise)" : ""
                let one = renderers.count == 1
                let kind =
                    device == .mac
                    ? (one ? "renderer process" : "renderer processes")
                    : (one ? "simulator" : "simulators")
                print(
                    "\(device): \(results.count) snapshots on \(renderers.count) \(kind): \(counts.matched) matched\(glass), \(counts.new) new, \(counts.rerecorded) re-recorded, \(counts.failed) failed."
                        + (restarts > 0
                            ? " The renderer crashed or hung and was restarted \(restarts) times:\n"
                                + incidents.map { "  \($0)" }.joined(separator: "\n")
                            : ""))
                // In story order, however the simulators shared them.
                return (results.sorted { $0.index < $1.index }.map(\.result), failed)
            }
        }

        private var isDrained: Bool { lock.withLock { next >= items.count } }

        private func work(with renderer: RestartingRenderer, in group: DispatchGroup) {
            group.enter()
            Thread.detachNewThread { [self] in
                defer { group.leave() }
                while let index = lock.withLock({ () -> Int? in
                    guard next < items.count else { return nil }
                    defer { next += 1 }
                    return next
                }) {
                    check(items[index], at: index, with: renderer)
                    lock.withLock { finished += 1 }
                }
            }
        }

        /// A Mac renderer process, restarted when it crashes or hangs.
        static func macRenderer(_ executable: URL) throws -> RestartingRenderer {
            try RestartingRenderer { try RendererProcess(executable: executable) }
        }

        /// Another renderer, if the remaining work repays starting it and, for a simulated
        /// device, a simulator is free.
        private func recruit() -> RestartingRenderer? {
            let (remaining, perItem, count) = lock.withLock {
                () -> (Int, Double?, Int) in
                // Pace only from real progress, not the first renderer's start.
                let pace =
                    finished >= 4
                    ? (ContinuousClock.now - started) / .seconds(1) / Double(finished) : nil
                return (items.count - next, pace, renderers.count)
            }
            guard let perItem else { return nil }
            if device == .mac {
                guard
                    Self.worthStarting(
                        remaining: remaining, perItem: perItem, renderers: count,
                        startCost: Self.macStart),
                    let executable = lock.withLock({ self.executable })
                else { return nil }
                do { return try Self.macRenderer(executable) } catch {
                    Renderers.progress("Couldn't start another renderer: \(error)")
                    return nil
                }
            }
            do {
                guard
                    let lease = try SimulatorPool.tryLease(
                        for: device, keepWarm: SimulatorIdleCommand.start,
                        accept: { warm in
                            Self.worthStarting(
                                remaining: remaining, perItem: perItem, renderers: count,
                                startCost: warm ? Self.warmStart : Self.coldStart)
                        })
                else { return nil }
                guard let app = lock.withLock({ self.app }) else {
                    lease.release()
                    return nil
                }
                return try Renderers.start(app, in: lease)
            } catch {
                Renderers.progress("Couldn't start another simulator: \(error)")
                return nil
            }
        }

        /// Whether another renderer repays starting it: the work left, shared by the `renderers`
        /// already at it, takes at least twice `startCost`, in seconds.
        static func worthStarting(
            remaining: Int, perItem: Double, renderers: Int, startCost: Double
        ) -> Bool {
            Double(remaining) * perItem / Double(max(renderers, 1)) > 2 * startCost
        }

        /// Renders `item`, verifies it, and records and prints the outcome.
        private func check(_ item: Item, at index: Int, with renderer: RestartingRenderer) {
            var environment = RenderEnvironment.standard(for: device)
            environment.appearance = item.appearance
            let subject =
                "\(item.story) (\(SnapshotStore.variantName(device: device, environment: environment)))"
            func record(_ result: TestCommand.Result, output: String?, _ count: () -> Void) {
                lock.withLock {
                    count()
                    if result.failure != nil { failed = true }
                    results.append((index, result))
                    if let output { print(output) }
                }
            }
            let result = TestCommand.Result(device: device, subject: subject, story: item.story)
            do {
                let rendered = try renderer.renderImage(item.story, in: environment)
                var snapshot = try Snapshot(
                    png: rendered.png, story: item.story, device: device, environment: environment)
                snapshot.glassRegions = rendered.glassRegions
                let verification = try project.store.verify(
                    snapshot, mode: mode, tolerance: tolerance)
                // Reports write artifacts and the review page, which are shared.
                let report = try lock.withLock {
                    try SnapshotReport(
                        verification, of: snapshot, mode: mode, store: project.store,
                        hints: TestCommand.hints)
                }
                guard let report else {
                    // Say so, so a reviewer knows glass was compared averaged.
                    var note: String?
                    if case .matched(let diff) = verification, diff.glassNoisePixels > 0 {
                        note =
                            "~ \(subject): matched, ignoring \(diff.glassNoisePixels) pixels of Liquid Glass noise\n"
                    }
                    record(result, output: note) {
                        counts.matched += 1
                        if note != nil { counts.glassNoise += 1 }
                    }
                    return
                }
                var reported = result
                if report.severity == .failure { reported.failure = report.message }
                record(
                    reported,
                    output: (report.severity == .failure ? "✗ " : "! ") + report.message + "\n"
                ) {
                    switch report.kind {
                    case .new: counts.new += 1
                    case .changed: counts.rerecorded += 1
                    default: counts.failed += 1
                    }
                }
            } catch {
                var failure = result
                failure.failure = "\(error)"
                record(failure, output: "✗ \(subject): \(error)\n") { counts.failed += 1 }
            }
        }
    }
#endif
