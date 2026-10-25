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

    @discardableResult
    static func run(_ arguments: [String]) -> Result {
        run(executable: "/bin/launchctl", arguments)
    }

    static func run(executable: String, _ arguments: [String]) -> Result {
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
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(data: data, encoding: .utf8))
    }

    /// Stops a user job and, when `persist`, keeps it from loading at the
    /// next login. Both are allowed in the user's own domain without a password.
    static func stop(_ job: LaunchJob, persist: Bool) -> Bool {
        let bootout = run(["bootout", job.serviceTarget])
        if persist { run(["disable", job.serviceTarget]) }
        // 3: "No such process", the job was not loaded. Still a success.
        return bootout.status == 0 || bootout.status == 3 || bootout.status == 113
    }

    /// Lets a job load again and, when it was loaded before, loads it now.
    static func start(_ job: LaunchJob, load: Bool) {
        run(["enable", job.serviceTarget])
        if load, let plist = job.plistPath, FileManager.default.fileExists(atPath: plist) {
            run(["bootstrap", job.domain.target, plist])
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
            ["-e", "do shell script \"\(script)\" with administrator privileges"]
        )
        return result.status == 0
    }

    /// A path quoted for `/bin/sh`.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
