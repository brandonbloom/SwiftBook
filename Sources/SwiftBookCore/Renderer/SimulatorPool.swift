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
        static var lockDirectory: URL {
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appending(path: "SwiftBook/Simulators", directoryHint: .isDirectory)
        }

        /// Leases a simulator for `device`, booted. While every one in the pool is in use, it
        /// tells `waiting` once and waits: waiting for a simulator is never a timeout.
        public static func lease(
            for device: Device, size: Int = size(), waiting: (String) -> Void = { _ in }
        ) throws -> SimulatorLease {
            var announced = false
            while true {
                if let (number, lock) = try claim(device, size: size) {
                    do {
                        let simulator = try Simulator.dedicated(for: device, number: number)
                        return SimulatorLease(simulator: simulator, number: number, lock: lock)
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
        /// Its place in the pool, from 1.
        public let number: Int
        private let lock: FileLock

        init(simulator: Simulator, number: Int, lock: FileLock) {
            self.simulator = simulator
            self.number = number
            self.lock = lock
        }

        /// Gives the simulator back. Extra simulators shut down, so they don't hold memory while
        /// idle; the first stays booted for the next run.
        public func release() {
            guard !lock.isReleased else { return }
            if number > 1 { simulator.shutdown() }
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
