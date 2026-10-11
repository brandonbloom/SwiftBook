#if os(macOS)
    import Foundation

    /// SwiftBook's simulators for each device class, shared by every run on this Mac.
    ///
    /// A simulator shows one app at a time and suspends the rest, so two runs can't share one:
    /// each would suspend the other's renderer mid-render, until it timed out. Each run leases a
    /// simulator of its own instead, by holding an exclusive lock on a file, and runs beyond the
    /// pool's size wait for one. A lock ends with its process, so a crashed run can't hold one.
    public enum SimulatorPool {
        /// The variable that sets how many simulators each device class may have.
        public static let sizeVariable = "SWIFTBOOK_SIMULATORS"

        /// The memory budgeted for each booted simulator. An iPhone simulator's processes
        /// measured 3.3 GB, an iPad's 3.0 GB, and an Apple TV's 2.0 GB, plus the Mac-side
        /// processes that draw them.
        static let memoryPerSimulator: UInt64 = 4 << 30

        /// How many simulators each device class may have: `SWIFTBOOK_SIMULATORS`, or else as
        /// many as fit in half the Mac's memory, at most one for every two performance cores.
        /// Always at least one.
        public static func size(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            memory: UInt64 = ProcessInfo.processInfo.physicalMemory,
            performanceCores: Int = performanceCores()
        ) -> Int {
            if let value = environment[sizeVariable], let size = Int(value), size > 0 {
                return size
            }
            let byMemory = Int(memory / 2 / memoryPerSimulator)
            return max(1, min(byMemory, performanceCores / 2))
        }

        /// The Mac's performance cores, or all its cores if it doesn't distinguish them.
        public static func performanceCores() -> Int {
            var cores: Int32 = 0
            var size = MemoryLayout<Int32>.size
            if sysctlbyname("hw.perflevel0.physicalcpu", &cores, &size, nil, 0) == 0, cores > 0 {
                return Int(cores)
            }
            return ProcessInfo.processInfo.activeProcessorCount
        }

        /// Where the pool's lock files live.
        public static var lockDirectory: URL {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "SwiftBook/Simulators", directoryHint: .isDirectory)
        }

        /// Leases a simulator for `device`, booted. While every one in the pool is in use, it
        /// tells `waiting` once and waits: waiting for a simulator is never a timeout.
        ///
        /// `keepWarm` is called when an extra simulator is released, instead of shutting it down.
        /// It should arrange for ``shutDownWhenIdle(_:number:idle:in:)`` to run, in a process
        /// that outlives this one.
        public static func lease(
            for device: Device, size: Int = size(), waiting: (String) -> Void = { _ in },
            keepWarm: (@Sendable (Device, Int) -> Void)? = nil
        ) throws -> SimulatorLease {
            var announced = false
            while true {
                if let (number, lock) = try claim(device, size: size) {
                    do {
                        let simulator = try Simulator.dedicated(for: device, number: number)
                        return SimulatorLease(
                            simulator: simulator, device: device, number: number, lock: lock,
                            keepWarm: keepWarm)
                    } catch {
                        lock.release()
                        throw error
                    }
                }
                if !announced {
                    let name = (try? Simulator.deviceType(for: device).name) ?? "\(device)"
                    let busy =
                        size == 1
                        ? "SwiftBook's \(name) simulator is in use by another run"
                        : "all \(size) of SwiftBook's \(name) simulators are in use by other runs"
                    waiting(
                        "Waiting for a simulator: \(busy). Set \(sizeVariable) to allow more.")
                    announced = true
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        /// How long an extra simulator stays booted after its last run, for the next one. Runs
        /// often overlap in bursts, and booting and installing on a cold simulator costs about
        /// 15 s.
        public static let idleTime = Duration.seconds(300)

        /// Records that `device`'s simulator `number` was just released.
        static func markReleased(_ device: Device, number: Int, in directory: URL = lockDirectory) {
            try? Data(String(Date().timeIntervalSince1970).utf8).write(
                to: directory.appending(path: "\(device)-\(number).released"))
        }

        /// When `device`'s simulator `number` was last released, if it's recorded.
        static func lastReleased(_ device: Device, number: Int, in directory: URL) -> Date? {
            (try? String(
                contentsOf: directory.appending(path: "\(device)-\(number).released"),
                encoding: .utf8))
                .flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
        }

        /// Shuts `device`'s simulator `number` down once it has been idle for `idle`: released,
        /// and not leased since. If another run holds it, this returns without waiting; that run's
        /// release arranges the next shutdown. Returns whether it shut the simulator down.
        @discardableResult
        public static func shutDownWhenIdle(
            _ device: Device, number: Int, idle: Duration = idleTime,
            in directory: URL = lockDirectory, shutdown: (() throws -> Void)? = nil
        ) throws -> Bool {
            let idleSeconds = idle / .seconds(1)
            while true {
                let released = lastReleased(device, number: number, in: directory) ?? .distantPast
                let remaining = idleSeconds - Date().timeIntervalSince(released)
                if remaining > 0 {
                    Thread.sleep(forTimeInterval: remaining)
                    continue
                }
                guard let lock = FileLock(directory.appending(path: "\(device)-\(number).lock"))
                else { return false }
                defer { lock.release() }
                // Released again while this waited for the lock: start over.
                if let again = lastReleased(device, number: number, in: directory),
                    Date().timeIntervalSince(again) < idleSeconds
                {
                    continue
                }
                if let shutdown {
                    try shutdown()
                } else {
                    try Simulator.dedicated(for: device, number: number, boot: false).shutdown()
                }
                return true
            }
        }

        /// The lowest-numbered free simulator for `device`, locked, or `nil` if all `size` are
        /// in use.
        static func claim(_ device: Device, size: Int, in directory: URL = lockDirectory) throws
            -> (number: Int, lock: FileLock)?
        {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            for number in 1...max(size, 1) {
                if let lock = FileLock(directory.appending(path: "\(device)-\(number).lock")) {
                    return (number, lock)
                }
            }
            return nil
        }
    }

    /// A simulator held for one run, until it's released or the run's process exits.
    public final class SimulatorLease: Sendable {
        public let simulator: Simulator
        public let device: Device
        /// Its place in the pool, from 1.
        public let number: Int
        private let lock: FileLock
        private let keepWarm: (@Sendable (Device, Int) -> Void)?

        init(
            simulator: Simulator, device: Device, number: Int, lock: FileLock,
            keepWarm: (@Sendable (Device, Int) -> Void)?
        ) {
            self.simulator = simulator
            self.device = device
            self.number = number
            self.lock = lock
            self.keepWarm = keepWarm
        }

        /// Gives the simulator back. The first stays booted for the next run. An extra one shuts
        /// down, so it doesn't hold memory while idle, unless the lease keeps it warm: then it
        /// stays booted until it has been idle for ``SimulatorPool/idleTime``.
        public func release() {
            guard !lock.isReleased else { return }
            if number > 1 {
                if let keepWarm {
                    SimulatorPool.markReleased(device, number: number)
                    keepWarm(device, number)
                } else {
                    simulator.shutdown()
                }
            }
            lock.release()
        }
    }

    /// An exclusive `flock` on a file, held until released or until the process exits.
    final class FileLock: @unchecked Sendable {
        // Unchecked: `state` guards the descriptor.

        private let state = NSLock()
        private var descriptor: Int32?

        /// Locks `url`, or returns `nil` if another holder has it.
        init?(_ url: URL) {
            let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
            guard descriptor >= 0 else { return nil }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                close(descriptor)
                return nil
            }
            self.descriptor = descriptor
        }

        var isReleased: Bool { state.withLock { descriptor == nil } }

        func release() {
            state.withLock {
                guard let descriptor else { return }
                flock(descriptor, LOCK_UN)
                close(descriptor)
                self.descriptor = nil
            }
        }

        deinit { release() }
    }
#endif
