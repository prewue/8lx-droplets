import Darwin
import Foundation

/// The part of closing and restoring that blocks: launchctl, signals and the
/// wait between them. Runs off the main thread.
enum Closer {
    struct Outcome: Sendable {
        let jobs: [StoppedJob]
        let killed: Int
        let adminRefused: Bool
    }

    static func stop(_ group: AppGroup, persist: Bool, includeSystem: Bool, scanner: ProcessScanner) -> Outcome {
        var stopped: [StoppedJob] = []

        // 1. The user's jobs first, so launchd has nothing left to restart.
        for job in group.jobs where job.domain == .user {
            _ = Launchctl.stop(job, persist: persist)
            stopped.append(StoppedJob(job: job, wasLoaded: group.loadedLabels.contains(job.label)))
        }

        // 2. System services, behind one administrator prompt.
        var adminRefused = false
        let rootProcesses = group.processes.filter { $0.isPrivileged && $0.kind != .system }
        let systemJobs = group.jobs.filter { $0.domain == .system && $0.hasSafeLabel }
        if includeSystem, !(systemJobs.isEmpty && rootProcesses.isEmpty) {
            var commands: [String] = []
            for job in systemJobs {
                commands.append("/bin/launchctl bootout \(job.serviceTarget) 2>/dev/null")
                if persist { commands.append("/bin/launchctl disable \(job.serviceTarget)") }
            }
            if !rootProcesses.isEmpty {
                commands.append("/bin/kill -TERM \(rootProcesses.map { String($0.pid) }.joined(separator: " ")) 2>/dev/null")
            }
            // The batch ends in `true`: a job that was not loaded is no failure.
            commands.append("true")
            if Launchctl.runAsAdministrator(commands) {
                // Unknown whether each was loaded; bootstrapping one that was
                // not is harmless, so every one goes back.
                stopped += systemJobs.map { StoppedJob(job: $0, wasLoaded: true) }
            } else {
                adminRefused = true
            }
        }

        // 3. Every process of the group still running.
        var targets: [pid_t: String] = [:]
        for process in group.processes where !process.isPrivileged && process.kind != .system {
            targets[process.pid] = process.path
        }
        let killed = end(targets, scanner: scanner)
        return Outcome(jobs: stopped, killed: killed, adminRefused: adminRefused)
    }

    /// Ends processes: SIGTERM, then SIGKILL to what is left after 2.5 s.
    /// Children started since the scan go with their parents, and the same
    /// executable started again by launchd goes too; nothing else. A pid only
    /// counts while it still runs the same executable, so a recycled pid is
    /// never hit. Returns how many were asked to end.
    @discardableResult
    static func end(_ initial: [pid_t: String], scanner: ProcessScanner = ProcessScanner()) -> Int {
        var targets = initial
        let paths = Set(targets.values)
        var fresh = scanner.scan(signatures: false).filter {
            $0.uid == getuid() && !BundlePath.isSystemManaged($0.path) && $0.pid != getpid() && targets[$0.pid] == nil
        }
        var grew = true
        while grew {
            grew = false
            fresh.removeAll { process in
                let child = targets[process.ppid] != nil
                let respawn = process.ppid <= 1 && !process.hasTerminal && paths.contains(process.path)
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

    /// Enables every stopped job again and loads the ones that were loaded.
    static func start(_ jobs: [StoppedJob]) {
        for stopped in jobs where stopped.job.domain == .user {
            Launchctl.start(stopped.job, load: stopped.wasLoaded)
        }
        let system = jobs.filter { $0.job.domain == .system && $0.job.hasSafeLabel }
        guard !system.isEmpty else { return }
        var commands: [String] = []
        for stopped in system {
            commands.append("/bin/launchctl enable \(stopped.job.serviceTarget)")
            if stopped.wasLoaded, let plist = stopped.job.plistPath {
                commands.append("/bin/launchctl bootstrap system \(Launchctl.quoted(plist)) 2>/dev/null")
            }
        }
        commands.append("true")
        _ = Launchctl.runAsAdministrator(commands)
    }
}
