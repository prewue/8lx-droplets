import Darwin
import Foundation

/// The launchd domain a job lives in.
enum LaunchDomain: String, Codable, Sendable {
    /// The logged-in user's GUI domain: LaunchAgents. Ours to stop.
    case user
    /// The system domain: LaunchDaemons, running as root.
    case system

    var target: String {
        switch self {
        case .user: return "gui/\(getuid())"
        case .system: return "system"
        }
    }
}

/// One launchd job, from its plist.
struct LaunchJob: Codable, Sendable, Hashable, Identifiable {
    let label: String
    let plistPath: String?
    let domain: LaunchDomain
    /// The executable the job runs.
    let program: String?
    /// launchd starts it again the moment it exits.
    let keepAlive: Bool
    /// launchd starts it at login or boot.
    let runAtLoad: Bool
    /// Bundle ids of the apps this job belongs to (macOS 13's Login Items key).
    let associatedBundleIDs: [String]

    var id: String { "\(domain.rawValue)/\(label)" }
    var serviceTarget: String { "\(domain.target)/\(label)" }

    /// Labels go into shell commands for the administrator route; only the
    /// characters launchd labels use in practice are let through.
    var hasSafeLabel: Bool {
        !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || "._-".contains($0) }
    }
}

/// Everything launchd knows that K*llTree needs: the job plists on disk and
/// which of the user's jobs are loaded, with their pids.
struct LaunchCatalog: Sendable {
    var jobs: [LaunchJob] = []
    /// Loaded user-domain jobs: label → pid, or nil when loaded but idle.
    var loaded: [String: pid_t?] = [:]

    var jobByPID: [pid_t: String] {
        var map: [pid_t: String] = [:]
        for (label, pid) in loaded {
            if let pid { map[pid] = label }
        }
        return map
    }

    static func read(appBundles: [String]) -> LaunchCatalog {
        var catalog = LaunchCatalog()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var folders: [(String, LaunchDomain)] = [
            (home + "/Library/LaunchAgents", .user),
            ("/Library/LaunchAgents", .user),
            ("/Library/LaunchDaemons", .system)
        ]
        // Jobs an app registers with SMAppService live inside its bundle.
        for app in appBundles {
            folders.append((app + "/Contents/Library/LaunchAgents", .user))
            folders.append((app + "/Contents/Library/LaunchDaemons", .system))
        }
        var seen = Set<String>()
        for (folder, domain) in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where name.hasSuffix(".plist") {
                let path = folder + "/" + name
                guard let job = parse(plistAt: path, domain: domain, folder: folder), seen.insert(job.id).inserted else { continue }
                catalog.jobs.append(job)
            }
        }
        catalog.loaded = loadedUserJobs()
        return catalog
    }

    private static func parse(plistAt path: String, domain: LaunchDomain, folder: String) -> LaunchJob? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = plist["Label"] as? String else {
            return nil
        }
        var program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
        // SMAppService jobs name their executable relative to the app bundle.
        if program == nil, let relative = plist["BundleProgram"] as? String,
           let range = folder.range(of: "/Contents/Library/") {
            program = String(folder[..<range.lowerBound]) + "/" + relative
        }
        let keepAlive: Bool
        switch plist["KeepAlive"] {
        case let flag as Bool: keepAlive = flag
        case is [String: Any]: keepAlive = true
        default: keepAlive = false
        }
        return LaunchJob(
            label: label,
            plistPath: path,
            domain: domain,
            program: program,
            keepAlive: keepAlive,
            runAtLoad: plist["RunAtLoad"] as? Bool ?? false,
            associatedBundleIDs: plist["AssociatedBundleIdentifiers"] as? [String]
                ?? (plist["AssociatedBundleIdentifiers"] as? String).map { [$0] } ?? []
        )
    }

    /// `launchctl list`: "PID\tStatus\tLabel", a dash for an idle job.
    private static func loadedUserJobs() -> [String: pid_t?] {
        guard let output = Launchctl.run(["list"]).output else { return [:] }
        var loaded: [String: pid_t?] = [:]
        for line in output.split(separator: "\n").dropFirst() {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { continue }
            let label = String(fields[2])
            loaded[label] = pid_t(fields[0])
        }
        return loaded
    }
}

/// Runs `launchctl` and, for the system domain, the same through an
/// administrator prompt.
enum Launchctl {
    struct Result: Sendable {
        let status: Int32
        let output: String?
    }

    /// How long a read may take, and a change: launchd waits for a job to exit
    /// before a bootout returns. The password prompt waits for a person.
    static let readDeadline: TimeInterval = 10
    static let changeDeadline: TimeInterval = 30
    static let passwordDeadline: TimeInterval = 120

    @discardableResult
    static func run(_ arguments: [String], timeout: TimeInterval = readDeadline, cancellable: Bool = true) -> Result {
        run(executable: "/bin/launchctl", arguments, timeout: timeout, cancellable: cancellable)
    }

    /// Runs a tool off the main actor and gives up at the deadline, taking its
    /// process group with it: the tool's own group, never Droppy's. Output is
    /// read while it runs, so a full pipe cannot stall it. Blocks its caller.
    static func run(executable: String, _ arguments: [String], timeout: TimeInterval = readDeadline, cancellable: Bool = true) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: nil)
        }
        let pid = process.processIdentifier
        if cancellable { Running.add(pid) }
        defer { Running.remove(pid) }

        let exited = DispatchSemaphore(value: 0)
        let deadline = DispatchWorkItem { Self.stop(group: pid, exited: exited) }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)

        let reader = pipe.fileHandleForReading
        let output = OutputBox()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            output.data = reader.readDataToEndOfFile()
            read.signal()
        }
        process.waitUntilExit()
        exited.signal()
        deadline.cancel()
        // A child that left the group can keep the pipe open: do not wait for it.
        _ = read.wait(timeout: .now() + 1)
        return Result(status: process.terminationStatus, output: String(data: output.data, encoding: .utf8))
    }

    private static func stop(group pid: pid_t, exited: DispatchSemaphore) {
        kill(-pid, SIGTERM)
        // Only while it has not exited: a pid that has can mean something else.
        if exited.wait(timeout: .now() + 2) == .timedOut { kill(-pid, SIGKILL) }
    }

    /// The droplet is being switched off: scans and an open password prompt
    /// stop with it. Changes already under way finish, or their record lies.
    static func cancelRunning() {
        for pid in Running.all { kill(-pid, SIGTERM) }
    }

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    private enum Running {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var pids = Set<pid_t>()

        static var all: Set<pid_t> { lock.withLock { pids } }
        static func add(_ pid: pid_t) { _ = lock.withLock { pids.insert(pid) } }
        static func remove(_ pid: pid_t) { _ = lock.withLock { pids.remove(pid) } }
    }

    /// Stops a user job and, when `persist`, keeps it from loading at the
    /// next login. Both are allowed in the user's own domain without a password.
    static func stop(_ job: LaunchJob, persist: Bool) -> Bool {
        let bootout = run(["bootout", job.serviceTarget], timeout: changeDeadline, cancellable: false)
        // 3 and 113: the job was not loaded. Still a success.
        guard bootout.status == 0 || bootout.status == 3 || bootout.status == 113 else { return false }
        if persist { run(["disable", job.serviceTarget], cancellable: false) }
        return true
    }

    /// The labels the person, or K*llTree, has disabled in a domain.
    static func disabledLabels(in domain: LaunchDomain) -> Set<String> {
        parseDisabled(run(["print-disabled", domain.target]).output ?? "")
    }

    /// `"label" => disabled` per line; older systems say `true`.
    static func parseDisabled(_ output: String) -> Set<String> {
        var labels = Set<String>()
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: " => ")
            guard parts.count == 2 else { continue }
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            guard state == "disabled" || state == "true" else { continue }
            labels.insert(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")))
        }
        return labels
    }

    static func isLoaded(_ job: LaunchJob) -> Bool {
        run(["print", job.serviceTarget]).status == 0
    }

    /// A job known only from `launchctl list` has no plist yet: launchd says
    /// where it came from, or Restore could not load it again.
    static func resolved(_ job: LaunchJob) -> LaunchJob {
        guard job.plistPath == nil, let output = run(["print", job.serviceTarget]).output else { return job }
        let path = output.split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("path = ") }
            .map { String($0.dropFirst("path = ".count)) }
        guard let path, path.hasPrefix("/") else { return job }
        return LaunchJob(
            label: job.label, plistPath: path, domain: job.domain, program: job.program,
            keepAlive: job.keepAlive, runAtLoad: job.runAtLoad, associatedBundleIDs: job.associatedBundleIDs
        )
    }

    /// Lets a job load again and, when it was loaded before, loads it now.
    static func start(_ job: LaunchJob, load: Bool, enable: Bool = true) {
        if enable { run(["enable", job.serviceTarget], cancellable: false) }
        if load, let plist = job.plistPath, FileManager.default.fileExists(atPath: plist) {
            run(["bootstrap", job.domain.target, plist], timeout: changeDeadline, cancellable: false)
        }
    }

    /// One administrator prompt for a whole batch of root commands.
    static func runAsAdministrator(_ commands: [String]) -> Bool {
        guard !commands.isEmpty else { return true }
        let script = commands.joined(separator: "; ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let result = run(
            executable: "/usr/bin/osascript",
            ["-e", "do shell script \"\(script)\" with administrator privileges"],
            timeout: passwordDeadline
        )
        return result.status == 0
    }

    /// A path quoted for `/bin/sh`.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
