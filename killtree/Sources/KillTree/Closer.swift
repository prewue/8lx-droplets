import Darwin
import Foundation

/// The part of closing and restoring that blocks: launchctl, signals and the
/// wait between them. Runs off the main thread.
enum Closer {
    struct Outcome: Sendable {
        let jobs: [StoppedJob]
        /// Labels launchd refused to stop: they are not kept closed.
        let failedJobs: [String]
        let killed: Int
        let adminRefused: Bool
    }

    /// How far back a respawned process may have started: the list on screen
    /// can be a scan's interval old, and a close starts from that list.
    static let respawnWindow: TimeInterval = 5

    static func stop(_ group: AppGroup, persist: Bool, includeSystem: Bool, scanner: ProcessScanner) -> Outcome {
        let since = Date().addingTimeInterval(-respawnWindow)
        var stopped: [StoppedJob] = []
        var failed: [String] = []

        // 1. The user's jobs first, so launchd has nothing left to restart.
        let disabled = Launchctl.disabledLabels(in: .user)
        for job in group.jobs where job.domain == .user {
            if Launchctl.stop(job, persist: persist) {
                stopped.append(StoppedJob(job: job, wasLoaded: group.loadedLabels.contains(job.label), wasDisabled: disabled.contains(job.label)))
            } else {
                failed.append(job.label)
            }
        }

        // 2. System services, behind one administrator prompt.
        var adminRefused = false
        let rootProcesses = group.processes.filter { $0.isPrivileged && $0.kind != .system }
        let systemJobs = group.jobs.filter { $0.domain == .system && $0.hasSafeLabel }
        if includeSystem, !(systemJobs.isEmpty && rootProcesses.isEmpty) {
            // Read before they are stopped: Restore gives back this, no more.
            let systemDisabled = Launchctl.disabledLabels(in: .system)
            let before = systemJobs.map { StoppedJob(job: $0, wasLoaded: Launchctl.isLoaded($0), wasDisabled: systemDisabled.contains($0.label)) }
            var commands: [String] = []
            for job in systemJobs {
                commands.append("/bin/launchctl bootout \(job.serviceTarget) 2>/dev/null")
                if persist { commands.append("/bin/launchctl disable \(job.serviceTarget)") }
            }
            commands += rootProcesses.map { rootKillCommand(pid: $0.pid, path: $0.path) }
            // The batch ends in `true`: a job that was not loaded is no failure.
            commands.append("true")
            if Launchctl.runAsAdministrator(commands) {
                stopped += before
            } else {
                adminRefused = true
            }
        }

        // 3. Every process of the group still running.
        var targets: [pid_t: String] = [:]
        for process in group.processes where !process.isPrivileged && process.kind != .system {
            targets[process.pid] = process.path
        }
        // Only what launchd runs can come back on its own.
        let respawning = Set(group.processes.filter { $0.label != nil }.map(\.path))
            .union(group.jobs.compactMap(\.program))
        let killed = end(targets, respawning: respawning, since: since, scanner: scanner)
        return Outcome(jobs: stopped, failedJobs: failed, killed: killed, adminRefused: adminRefused)
    }

    /// A root SIGTERM for one process. The password prompt can stay open for
    /// long enough that the pid means something else by the time it runs, so
    /// the batch looks at what the pid runs first.
    static func rootKillCommand(pid: pid_t, path: String) -> String {
        "[ \"$(/bin/ps -o comm= -p \(pid))\" = \(Launchctl.quoted(path)) ] && /bin/kill -TERM \(pid) 2>/dev/null"
    }

    /// Ends processes: SIGTERM, then SIGKILL to what is left after 2.5 s.
    /// Children started since the scan go with their parents. A process with
    /// no parent left goes only if it runs one of `respawning` and started
    /// after `since`: launchd bringing it back. An unrelated copy of the same
    /// executable, started earlier, is someone else's. A pid only counts while
    /// it still runs the same executable, so a recycled pid is never hit.
    /// Returns how many were asked to end.
    @discardableResult
    static func end(
        _ initial: [pid_t: String],
        respawning: Set<String> = [],
        since: Date = .distantFuture,
        scanner: ProcessScanner = ProcessScanner()
    ) -> Int {
        var targets = initial
        var fresh = scanner.scan(signatures: false).filter {
            $0.uid == getuid() && !BundlePath.isSystemManaged($0.path) && $0.pid != getpid() && targets[$0.pid] == nil
        }
        var grew = true
        while grew {
            grew = false
            fresh.removeAll { process in
                let child = targets[process.ppid] != nil
                let respawn = process.ppid <= 1 && !process.hasTerminal && respawning.contains(process.path)
                    && (process.startedAt ?? .distantPast) >= since
                guard child || respawn else { return false }
                targets[process.pid] = process.path
                grew = true
                return true
            }
        }
        var killed = 0
        for (pid, path) in targets where ProcessScanner.path(of: pid) == path {
            if kill(pid, SIGTERM) == 0 { killed += 1 }
        }
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline, targets.contains(where: { ProcessScanner.isAlive($0.key) && ProcessScanner.path(of: $0.key) == $0.value }) {
            usleep(150_000)
        }
        for (pid, path) in targets where ProcessScanner.isAlive(pid) && ProcessScanner.path(of: pid) == path {
            kill(pid, SIGKILL)
        }
        return killed
    }

    /// Gives every stopped job back as it was: enabled unless the person had
    /// disabled it, loaded if it was loaded. Returns false when the password
    /// for the system's jobs was refused, so nothing of those came back.
    @discardableResult
    static func start(_ jobs: [StoppedJob]) -> Bool {
        for stopped in jobs where stopped.job.domain == .user {
            Launchctl.start(stopped.job, load: stopped.wasLoaded, enable: stopped.wasDisabled != true)
        }
        let system = jobs.filter { $0.job.domain == .system && $0.job.hasSafeLabel }
        guard !system.isEmpty else { return true }
        var commands: [String] = []
        for stopped in system {
            if stopped.wasDisabled != true { commands.append("/bin/launchctl enable \(stopped.job.serviceTarget)") }
            if stopped.wasLoaded, let plist = stopped.job.plistPath {
                commands.append("/bin/launchctl bootstrap system \(Launchctl.quoted(plist)) 2>/dev/null")
            }
        }
        commands.append("true")
        return Launchctl.runAsAdministrator(commands)
    }
}
