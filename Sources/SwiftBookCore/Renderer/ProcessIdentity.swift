#if os(macOS)
    import Darwin

    /// A process told apart from any later process that reuses its pid, by when it started.
    ///
    /// Signalling a bare pid is only safe for this process's own children, which keep their pid
    /// until they're waited on. Any other process's pid can go to a new process once it exits.
    struct ProcessIdentity: Equatable, Sendable {
        let pid: pid_t
        /// When the process started, in microseconds since 1970.
        let started: UInt64

        init(pid: pid_t, started: UInt64) {
            self.pid = pid
            self.started = started
        }

        /// The process `pid` names, or `nil` if there's none.
        init?(pid: pid_t) {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            self.init(
                pid: pid, started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec)
        }

        /// Whether the process still exists, under the same pid.
        var isRunning: Bool { ProcessIdentity(pid: pid) == self }
    }
#endif
