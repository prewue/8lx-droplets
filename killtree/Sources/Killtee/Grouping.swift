import Darwin
import Foundation

/// What a process is to its app, which decides what closing it means.
enum ProcessKind: Int, Sendable, Hashable, Comparable {
    /// The app the person opened.
    case app
    /// Inside the running app's bundle; it goes when the app goes.
    case bundled
    /// A launchd job: started at login, often restarted on exit.
    case agent
    /// Anything else of the vendor's running on its own.
    case helper
    /// Started by the system on its own schedule (app and system extensions).
    /// Shown, never stopped: the system would start it again at once.
    case system

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Lives on after the app is closed.
    var isBackground: Bool { self == .agent || self == .helper }

    var title: String {
        switch self {
        case .app: return "The app itself."
        case .bundled: return "Part of the open app; it ends with the app."
        case .agent: return "A launchd job: launchd starts it, at login or on demand."
        case .helper: return "Runs on its own, outside any open app."
        case .system: return "An extension macOS starts and stops itself. KillTee leaves it alone."
        }
    }
}

/// How sure KillTee is that a process belongs where it is listed.
enum Confidence: Int, Sendable, Comparable {
    case low, medium, high

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .low: return "Low: only the signature ties it to this vendor"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// One reason a process is listed where it is. Every process carries all
/// the reasons that held, and the tooltip shows them.
enum Evidence: Sendable, Hashable {
    case signed(organization: String?, team: String, verified: Bool?)
    case adhoc(identifier: String?)
    case insideBundle(app: String)
    case startedBy(String)
    case responsible(String)
    case launchdJob(label: String, keepAlive: Bool, runAtLoad: Bool)
    case declaredBy(app: String)
    case identifierMatches(identifier: String, app: String)
    case pathMentions(app: String)
    case runsAs(user: String)
    case vendorsOnlyApp(String)
    case menuBar
    case apple

    var text: String {
        switch self {
        case let .signed(organization, team, verified):
            let who = organization.map { "\($0) (\(team))" } ?? team
            switch verified {
            case true?: return "Signed by \(who); the running code matches the signature"
            case false?: return "Signed by \(who), but the running code no longer matches it (updated on disk?)"
            case nil: return "Signed by \(who)"
            }
        case let .adhoc(identifier):
            return "No developer signature\(identifier.map { " (\($0))" } ?? ""); tied by the evidence below"
        case let .insideBundle(app): return "Lives inside \(app).app"
        case let .startedBy(parent): return "Started by \(parent)"
        case let .responsible(app): return "macOS holds \(app) responsible for it"
        case let .launchdJob(label, keepAlive, runAtLoad):
            var text = "launchd job \(label)"
            if keepAlive { text += "; restarts when it exits" }
            if runAtLoad { text += "; starts at login" }
            return text
        case let .declaredBy(app): return "Its launchd job names \(app) as its app"
        case let .identifierMatches(identifier, app): return "Its identifier \(identifier) is \(app)'s"
        case let .pathMentions(app): return "Its folder is named after \(app)"
        case let .runsAs(user): return "Runs as \(user); closing it needs an administrator"
        case let .vendorsOnlyApp(app): return "\(app) is the only app installed from this developer"
        case .menuBar: return "A menu bar app"
        case .apple: return "Made by Apple. KillTee only quits it the normal way and never touches macOS's own services"
        }
    }

    /// How strongly it ties a process to one particular app of the vendor.
    var appWeight: Int {
        switch self {
        case .insideBundle: return 100
        case .declaredBy: return 80
        case .startedBy, .responsible: return 70
        case .identifierMatches: return 60
        case .vendorsOnlyApp: return 30
        case .pathMentions: return 20
        default: return 0
        }
    }
}

struct ProcessEntry: Identifiable, Sendable, Hashable {
    let pid: pid_t
    let name: String
    let path: String
    let memory: UInt64
    let kind: ProcessKind
    let label: String?
    let keepAlive: Bool
    /// Runs as root or a service account: only an administrator can end it.
    let isPrivileged: Bool
    var isMenuBar = false
    var evidence: [Evidence] = []
    var confidence: Confidence = .medium

    var id: pid_t { pid }
}

/// An app with the processes that belong to it, or a vendor's services that
/// belong to none of its apps in particular.
struct AppGroup: Identifiable, Sendable {
    /// "TEAMID|/Applications/Figma.app", or "TEAMID|shared".
    let id: String
    let teamID: String
    let name: String
    let organization: String?
    let iconPath: String?
    /// The app's bundle, `nil` for a vendor's shared services.
    let appPath: String?
    /// Window apps of this group that are open now.
    let runningApps: [String]
    let processes: [ProcessEntry]
    /// Its launchd jobs, loaded or not.
    let jobs: [LaunchJob]
    let loadedLabels: Set<String>
    /// The process KillTee runs in is part of it: shown, never closed.
    var isHost = false

    var isShared: Bool { appPath == nil }
    var isApple: Bool { teamID == "apple" }
    /// Opening shows something only when there are two kinds of process or
    /// more; one is already the row itself.
    var isExpandable: Bool { ProcessCluster.clusters(of: processes).count > 1 }
    var memory: UInt64 { processes.reduce(0) { $0 + $1.memory } }
    var backgroundProcesses: [ProcessEntry] { processes.filter { $0.kind.isBackground || ($0.kind == .app && $0.isMenuBar && !isAppRunning) } }
    var hasBackground: Bool { !backgroundProcesses.isEmpty }
    var isAppRunning: Bool { !runningApps.isEmpty }
    var restartingCount: Int { processes.filter(\.keepAlive).count }
    var privilegedCount: Int { processes.filter(\.isPrivileged).count }
    var closableProcesses: [ProcessEntry] { processes.filter { $0.kind != .system } }
    /// Jobs that bring something back at the next login.
    var startupJobs: [LaunchJob] {
        jobs.filter { $0.domain == .user && ($0.runAtLoad || $0.keepAlive || loadedLabels.contains($0.label)) }
    }
    /// Nothing runs, but jobs are set to start.
    var isIdle: Bool { processes.isEmpty }

    static func teamID(of id: String) -> String {
        String(id.split(separator: "|", maxSplits: 1).first ?? "")
    }
}

/// A process KillTee lists but never touches, and why.
struct HiddenProcess: Identifiable, Sendable, Hashable {
    enum Reason: Sendable, Hashable {
        /// Started from a terminal: a command-line tool someone is using.
        case terminal
        /// No developer signature and nothing ties it to an app.
        case unsigned
        /// Started by a process that is not its vendor's: a shell, an editor.
        case foreignParent(String)
        /// An interpreter (node, python…) running someone's script: the
        /// signer made the runtime, not what it runs.
        case runtime
        /// Droppy itself, which runs KillTee.
        case host

        var tag: String {
            switch self {
            case .terminal: return "terminal"
            case .unsigned: return "unsigned"
            case .foreignParent: return "child"
            case .runtime: return "runtime"
            case .host: return "Droppy"
            }
        }

        var explanation: String {
            switch self {
            case .terminal: return "Started from a terminal. It is a command-line tool someone is using, not something an app left behind."
            case .unsigned: return "No developer signature, and nothing ties it to an installed app (Homebrew services, scripts, dev servers). KillTee cannot tell whose it is."
            case let .foreignParent(parent): return "Started by \(parent), which is not its vendor's. It belongs to \(parent)."
            case .runtime: return "A language runtime running a script, often a dev server or an agent's tool. Its signature names who made the runtime, not whose script it runs."
            case .host: return "Droppy itself, which runs KillTee."
            }
        }
    }

    let pid: pid_t
    let name: String
    let path: String
    let memory: UInt64
    let reason: Reason
    var label: String?

    var id: pid_t { pid }
}

struct ScanResult: Sendable {
    var groups: [AppGroup] = []
    var hidden: [HiddenProcess] = []
    /// Terminal tools and servers, built from what the app groups left out.
    var tasks: [TaskGroup] = []
}

/// An app the person opened, as AppKit reports it.
struct RunningApp: Sendable, Hashable {
    let pid: pid_t
    let name: String
    let bundlePath: String?
    /// A menu bar app: kept open on purpose, but never what reopens a vendor.
    var isMenuBar = false
}

/// An installed app, for naming a vendor and drawing its icon when none of
/// its apps is open.
struct InstalledApp: Sendable, Hashable {
    let path: String
    let name: String
    let bundleID: String?
    let teamID: String?
}

enum AppDirectory {
    /// /Applications, one folder deep (Adobe keeps each app in its own
    /// folder), plus ~/Applications.
    static func read(scanner: ProcessScanner) -> [InstalledApp] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var bundles: [String] = []
        for root in ["/Applications", home + "/Applications"] {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for name in names {
                let path = root + "/" + name
                if name.hasSuffix(".app") {
                    bundles.append(path)
                } else if let inner = try? FileManager.default.contentsOfDirectory(atPath: path) {
                    bundles += inner.filter { $0.hasSuffix(".app") }.map { path + "/" + $0 }
                }
            }
        }
        return bundles.compactMap(app(at:)).compactMap { app in
            let signature = scanner.signature(at: app.path)
            guard signature?.isApple != true else { return nil }
            return InstalledApp(path: app.path, name: app.name, bundleID: app.bundleID, teamID: vendorID(signature, bundleID: app.bundleID))
        }
    }

    /// The Team ID, or for an app without one (signed ad hoc, like Macs Fan
    /// Control) a vendor of its own named after its bundle id, so its helpers
    /// can still be tied to it by their identifiers.
    static func vendorID(_ signature: CodeSignature?, bundleID: String?) -> String? {
        if let team = signature?.teamID { return team }
        guard signature?.isApple != true, let bundleID else { return nil }
        return "adhoc:" + bundleID
    }

    static func app(at path: String) -> (path: String, name: String, bundleID: String?)? {
        guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any] else { return nil }
        let name = info["CFBundleDisplayName"] as? String
            ?? info["CFBundleName"] as? String
            ?? ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return (path, name, info["CFBundleIdentifier"] as? String)
    }
}

/// Builds the groups from one scan, checking every process several ways.
///
/// 1. Vendor: the Team ID of the signature, verified against the running
///    code. Code without one is tied to a vendor only through its bundle id,
///    its bundle, its launchd job or its parent.
/// 2. Ownership: only what launchd or the vendor itself started counts.
///    Terminal tools and children of other apps are listed, never touched.
/// 3. App: inside the vendor, every process is scored against each of the
///    vendor's apps (bundle, launchd job, parent, responsibility, identifier,
///    folder). A clear winner takes it; otherwise it is the vendor's shared
///    services.
enum GroupBuilder {
    struct Input: Sendable {
        let processes: [RawProcess]
        let catalog: LaunchCatalog
        let runningApps: [RunningApp]
        let installed: [InstalledApp]
        /// The host's own team: closing Droppy from inside Droppy ends badly.
        let excludedTeams: Set<String>
        let ownPID: pid_t
        /// Listening TCP ports by pid, for the servers.
        var ports: [pid_t: [Int]] = [:]
        /// Apple's open apps, each with what macOS holds it responsible for.
        var appleApps: [AppleApp] = []
    }

    struct AppleApp: Sendable {
        let pid: pid_t
        let name: String
        let path: String
        let processes: [RawProcess]
    }

    private struct AppRef {
        let path: String
        let name: String
        let bundleID: String?
        let teamID: String?
    }

    static func build(_ input: Input, scanner: ProcessScanner) -> ScanResult {
        let me = getuid()
        var result = ScanResult()
        let byPID = Dictionary(input.processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let jobByPID = input.catalog.jobByPID
        let jobsByLabel = Dictionary(input.catalog.jobs.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })

        // Every app KillTee can attribute to: installed, and open from anywhere.
        var apps: [String: AppRef] = [:]
        for app in input.installed {
            apps[app.path] = AppRef(path: app.path, name: app.name, bundleID: app.bundleID, teamID: app.teamID)
        }
        // Window apps open from elsewhere count too; a menu bar helper running
        // out of Application Support is something to attribute, not an app.
        for running in input.runningApps where !running.isMenuBar {
            guard let path = running.bundlePath, apps[path] == nil, let app = AppDirectory.app(at: path) else { continue }
            let signature = scanner.signature(at: path)
            guard signature?.isApple != true else { continue }
            apps[path] = AppRef(path: path, name: app.name, bundleID: app.bundleID, teamID: AppDirectory.vendorID(signature, bundleID: app.bundleID))
        }
        let appsByTeam = Dictionary(grouping: apps.values.filter { $0.teamID != nil }, by: { $0.teamID! })
        let appsWithIDs = apps.values.filter { $0.bundleID != nil && $0.teamID != nil }

        // A menu bar app the person installed (LuLu, Droppy) is an app they
        // keep open. One that lives in Application Support or inside another
        // app's LoginItems is a helper with an icon, and is treated as one.
        let installedPaths = Set(input.installed.map(\.path))
        let runningByPID = Dictionary(
            input.runningApps
                .filter { !$0.isMenuBar || $0.bundlePath.map(installedPaths.contains) == true }
                .map { ($0.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        func name(of pid: pid_t) -> String {
            if let running = runningByPID[pid] { return running.name }
            if let path = byPID[pid]?.path ?? ProcessScanner.path(of: pid) { return BundlePath.displayName(for: path) }
            return "pid \(pid)"
        }

        /// The app whose bundle id an identifier or label extends:
        /// com.crystalidea.macsfancontrol.smcwrite → Macs Fan Control.
        func appExtending(_ identifier: String?) -> AppRef? {
            guard let identifier else { return nil }
            return appsWithIDs
                .filter { identifier == $0.bundleID! || identifier.hasPrefix($0.bundleID! + ".") }
                .max { $0.bundleID!.count < $1.bundleID!.count }
        }

        // 1. Vendor.
        var team: [pid_t: String] = [:]
        var evidence: [pid_t: [Evidence]] = [:]
        var organizations: [String: String] = [:]
        var unlinked: [RawProcess] = []
        for process in input.processes {
            let signature = process.signature
            if signature?.isApple == true { continue }
            if BundlePath.isRuntime(process.path) {
                result.hidden.append(hidden(process, .runtime, label: jobByPID[process.pid]))
                continue
            }
            if let teamID = signature?.teamID {
                if input.excludedTeams.contains(teamID) {
                    result.hidden.append(hidden(process, .host, label: jobByPID[process.pid]))
                    continue
                }
                team[process.pid] = teamID
                if let organization = signature?.organization { organizations[teamID] = organization }
                let verified = process.uid == me ? scanner.verifyRunning(pid: process.pid, path: process.path) : nil
                evidence[process.pid] = [.signed(organization: signature?.organization, team: teamID, verified: verified)]
            } else {
                unlinked.append(process)
            }
        }

        // Unsigned code: tied by its identifier, its bundle, or its job.
        var stillUnlinked: [RawProcess] = []
        for process in unlinked where process.pid != input.ownPID {
            let label = jobByPID[process.pid]
            var link: (AppRef, Evidence)?
            if let app = appExtending(process.signature?.identifier) {
                link = (app, .identifierMatches(identifier: process.signature!.identifier!, app: app.name))
            } else if let outer = BundlePath.outermostApp(in: process.path), let app = apps[outer], app.teamID != nil {
                link = (app, .insideBundle(app: app.name))
            } else if let label, let job = jobsByLabel[label],
                      let app = job.associatedBundleIDs.lazy.compactMap({ id in appsWithIDs.first { $0.bundleID == id } }).first {
                link = (app, .declaredBy(app: app.name))
            } else if let app = appExtending(label) {
                link = (app, .identifierMatches(identifier: label!, app: app.name))
            }
            if let (app, reason) = link, let teamID = app.teamID, !input.excludedTeams.contains(teamID) {
                team[process.pid] = teamID
                evidence[process.pid] = [.adhoc(identifier: process.signature?.identifier), reason]
            } else {
                stillUnlinked.append(process)
            }
        }
        // Their unsigned children follow them. Two passes for grandchildren.
        for _ in 0..<2 {
            for process in stillUnlinked where team[process.pid] == nil {
                if let parentTeam = team[process.ppid] {
                    team[process.pid] = parentTeam
                    evidence[process.pid] = [.adhoc(identifier: process.signature?.identifier), .startedBy(name(of: process.ppid))]
                }
            }
        }
        for process in stillUnlinked where team[process.pid] == nil {
            result.hidden.append(hidden(process, process.hasTerminal ? .terminal : .unsigned, label: jobByPID[process.pid]))
        }

        // 2. Ownership.
        var owned: [pid_t: Bool] = [:]
        func isOwned(_ pid: pid_t, depth: Int = 0) -> Bool {
            if let known = owned[pid] { return known }
            guard depth < 32, let process = byPID[pid], !process.hasTerminal else { return false }
            let answer: Bool
            if process.ppid <= 1 {
                answer = true
            } else if let parentTeam = team[process.ppid], parentTeam == team[pid] {
                answer = isOwned(process.ppid, depth: depth + 1)
            } else {
                answer = false
            }
            owned[pid] = answer
            return answer
        }
        for pid in Array(team.keys) where !isOwned(pid) {
            if let process = byPID[pid] {
                result.hidden.append(hidden(process, process.hasTerminal ? .terminal : .foreignParent(name(of: process.ppid)), label: jobByPID[pid]))
            }
            team[pid] = nil
        }

        // 3. App, by score.
        var appOf: [pid_t: String] = [:]
        for (pid, teamID) in team {
            guard let process = byPID[pid] else { continue }
            let candidates = appsByTeam[teamID] ?? []
            let label = jobByPID[pid]
            var best: (app: AppRef, score: Int, reasons: [Evidence])?
            var second = 0
            for app in candidates {
                var reasons: [Evidence] = []
                if process.path.hasPrefix(app.path + "/") { reasons.append(.insideBundle(app: app.name)) }
                if let label, let job = jobsByLabel[label], let id = app.bundleID, job.associatedBundleIDs.contains(id) {
                    reasons.append(.declaredBy(app: app.name))
                }
                if ancestors(of: pid, in: byPID).contains(where: { byPID[$0]?.path.hasPrefix(app.path + "/") == true }) {
                    reasons.append(.startedBy(app.name))
                }
                if let responsible = ProcessScanner.responsiblePID(of: pid),
                   (byPID[responsible]?.path ?? ProcessScanner.path(of: responsible))?.hasPrefix(app.path + "/") == true {
                    reasons.append(.responsible(app.name))
                }
                if let id = app.bundleID {
                    let identifier = process.signature?.identifier ?? ""
                    if identifier.hasPrefix(id + ".") || label?.hasPrefix(id + ".") == true {
                        reasons.append(.identifierMatches(identifier: identifier.isEmpty ? label! : identifier, app: app.name))
                    }
                }
                if pathMentions(process.path, app: app) { reasons.append(.pathMentions(app: app.name)) }
                let score = reasons.map(\.appWeight).reduce(0, +)
                if score > (best?.score ?? 0) {
                    second = best?.score ?? 0
                    best = (app, score, reasons)
                } else {
                    second = max(second, score)
                }
            }
            if let best, best.score >= 40, best.score - second >= 15 {
                appOf[pid] = best.app.path
                for reason in best.reasons where !(evidence[pid] ?? []).contains(reason) {
                    evidence[pid, default: []].append(reason)
                }
            } else if candidates.count == 1 {
                // A vendor with one app: everything of it is that app's.
                appOf[pid] = candidates[0].path
                var reasons = best?.reasons ?? []
                reasons.append(.vendorsOnlyApp(candidates[0].name))
                for reason in reasons where !(evidence[pid] ?? []).contains(reason) {
                    evidence[pid, default: []].append(reason)
                }
            }
        }

        // 4. Jobs, by the same signals.
        func appOfJob(_ job: LaunchJob, teamID: String) -> String? {
            let candidates = appsByTeam[teamID] ?? []
            if let program = job.program, let app = candidates.first(where: { program.hasPrefix($0.path + "/") }) { return app.path }
            if let app = candidates.first(where: { $0.bundleID.map(job.associatedBundleIDs.contains) == true }) { return app.path }
            if let app = appExtending(job.label), app.teamID == teamID { return app.path }
            return candidates.count == 1 ? candidates[0].path : nil
        }
        var jobsByKey: [String: [LaunchJob]] = [:]
        for job in input.catalog.jobs {
            let programSignature = job.program.flatMap { scanner.signature(at: $0) }
            var teamID = programSignature?.teamID
            if let teamID, organizations[teamID] == nil, let organization = programSignature?.organization {
                organizations[teamID] = organization
            }
            if teamID == nil {
                teamID = job.associatedBundleIDs.lazy.compactMap { id in appsWithIDs.first { $0.bundleID == id }?.teamID }.first
            }
            if teamID == nil { teamID = appExtending(job.label)?.teamID }
            guard let teamID, !input.excludedTeams.contains(teamID) else { continue }
            jobsByKey[key(teamID, appOfJob(job, teamID: teamID)), default: []].append(job)
        }

        // 5. Groups.
        var pidsByKey: [String: [pid_t]] = [:]
        for (pid, teamID) in team {
            pidsByKey[key(teamID, appOf[pid]), default: []].append(pid)
        }
        let keys = Set(pidsByKey.keys).union(jobsByKey.keys)
        let teamsWithAppGroups = Set(keys.filter { !$0.hasSuffix("|shared") }.map(AppGroup.teamID(of:)))
        for groupKey in keys {
            let teamID = AppGroup.teamID(of: groupKey)
            let appPath = groupKey.hasSuffix("|shared") ? nil : String(groupKey.dropFirst(teamID.count + 1))
            let pids = pidsByKey[groupKey] ?? []
            let jobs = jobsByKey[groupKey] ?? []
            let loaded = Set(jobs.map(\.label).filter { input.catalog.loaded.keys.contains($0) })
            if pids.isEmpty {
                // Nothing runs: listed only when it comes back at login.
                guard jobs.contains(where: { $0.domain == .user && ($0.runAtLoad || $0.keepAlive || loaded.contains($0.label)) }) else { continue }
            }

            var entries: [ProcessEntry] = []
            var openApps: [String] = []
            for pid in pids {
                guard let raw = byPID[pid] else { continue }
                let label = jobByPID[pid]
                let job = label.flatMap { jobsByLabel[$0] }
                let running = runningByPID[pid]
                let kind: ProcessKind
                if running != nil {
                    kind = .app
                } else if BundlePath.isSystemManaged(raw.path) {
                    kind = .system
                } else if let outer = BundlePath.outermostApp(in: raw.path),
                          input.runningApps.contains(where: { $0.bundlePath == outer && !$0.isMenuBar }) {
                    kind = .bundled
                } else if label != nil || raw.uid != me {
                    kind = .agent
                } else {
                    kind = .helper
                }
                if let running, !running.isMenuBar { openApps.append(running.name) }
                var reasons = evidence[pid] ?? []
                if let label, let job, !label.hasPrefix("application.") {
                    reasons.append(.launchdJob(label: label, keepAlive: job.keepAlive, runAtLoad: job.runAtLoad))
                }
                if raw.uid != me { reasons.append(.runsAs(user: ProcessScanner.userName(of: raw.uid))) }
                if running?.isMenuBar == true { reasons.append(.menuBar) }
                entries.append(ProcessEntry(
                    pid: pid,
                    name: running?.name ?? BundlePath.displayName(for: raw.path),
                    path: raw.path,
                    memory: raw.memory,
                    kind: kind,
                    label: label,
                    keepAlive: job?.keepAlive ?? false,
                    isPrivileged: raw.uid != me,
                    isMenuBar: running?.isMenuBar ?? false,
                    evidence: reasons,
                    confidence: confidence(of: reasons)
                ))
            }
            entries.sort { ($0.kind, $1.memory, $0.name) < ($1.kind, $0.memory, $1.name) }

            let app = appPath.flatMap { apps[$0] }
            let vendorApps = appsByTeam[teamID] ?? []
            let organization = organizations[teamID]
            let name: String
            if let app {
                name = app.name
            } else {
                let vendor = organization ?? vendorApps.min(by: { $0.name.count < $1.name.count })?.name
                    ?? entries.first?.name ?? jobs.first.map { Self.readableLabel($0.label) } ?? teamID
                name = teamsWithAppGroups.contains(teamID) ? "\(vendor) services" : vendor
            }
            let memberBundles = Set(entries.compactMap { BundlePath.outermostApp(in: $0.path) })
            let icon = app?.path
                ?? vendorApps.first(where: { memberBundles.contains($0.path) })?.path
                ?? vendorApps.min(by: { $0.name.count < $1.name.count })?.path
                ?? memberBundles.sorted().first
            result.groups.append(AppGroup(
                id: groupKey,
                teamID: teamID,
                name: name,
                organization: organization,
                iconPath: icon,
                appPath: appPath,
                runningApps: openApps.sorted(),
                processes: entries,
                jobs: jobs,
                loadedLabels: loaded
            ))
        }
        // The process KillTee runs in, and everything it started.
        var host: Set<pid_t> = [input.ownPID]
        for _ in 0..<3 {
            for process in input.processes where host.contains(process.ppid) { host.insert(process.pid) }
        }
        for index in result.groups.indices where result.groups[index].processes.contains(where: { host.contains($0.pid) }) {
            result.groups[index].isHost = true
        }

        // Apple's open apps: the app and what macOS holds it responsible for.
        for apple in input.appleApps {
            var entries = apple.processes.map { raw -> ProcessEntry in
                let isApp = raw.pid == apple.pid
                return ProcessEntry(
                    pid: raw.pid,
                    name: isApp ? apple.name : BundlePath.readableServiceName(raw.path),
                    path: raw.path,
                    memory: raw.memory,
                    kind: isApp ? .app : .bundled,
                    label: nil,
                    keepAlive: false,
                    isPrivileged: false,
                    evidence: isApp ? [.apple] : [.apple, .responsible(apple.name)],
                    confidence: .high
                )
            }
            entries.sort { ($0.kind, $1.memory, $0.name) < ($1.kind, $0.memory, $1.name) }
            result.groups.append(AppGroup(
                id: "apple|\(apple.path)",
                teamID: "apple",
                name: apple.name,
                organization: "Apple",
                iconPath: apple.path,
                appPath: apple.path,
                runningApps: [apple.name],
                processes: entries,
                jobs: [],
                loadedLabels: []
            ))
        }

        result.groups.sort { ($0.hasBackground ? 0 : 1, $1.memory, $0.name) < ($1.hasBackground ? 0 : 1, $0.memory, $1.name) }
        result.hidden.sort { ($1.memory, $0.name) < ($0.memory, $1.name) }
        result.tasks = TaskBuilder.build(
            hidden: result.hidden,
            byPID: byPID,
            jobByPID: jobByPID,
            jobsByLabel: jobsByLabel,
            ports: input.ports
        )
        return result
    }

    /// "com.oracle.java.Java-Updater" → "Oracle", for a job nothing else names.
    static func readableLabel(_ label: String) -> String {
        let parts = label.split(separator: ".")
        guard parts.count >= 2 else { return label }
        return parts[1].prefix(1).uppercased() + parts[1].dropFirst()
    }

    private static func key(_ teamID: String, _ appPath: String?) -> String {
        "\(teamID)|\(appPath ?? "shared")"
    }

    private static func hidden(_ process: RawProcess, _ reason: HiddenProcess.Reason, label: String?) -> HiddenProcess {
        HiddenProcess(
            pid: process.pid,
            name: BundlePath.displayName(for: process.path),
            path: process.path,
            memory: process.memory,
            reason: reason,
            label: label
        )
    }

    private static func ancestors(of pid: pid_t, in byPID: [pid_t: RawProcess]) -> [pid_t] {
        var chain: [pid_t] = []
        var current = byPID[pid]?.ppid ?? 0
        while current > 1, chain.count < 16 {
            chain.append(current)
            current = byPID[current]?.ppid ?? 0
        }
        return chain
    }

    /// "~/Library/Application Support/Figma/FigmaAgent.app" mentions Figma.
    private static func pathMentions(_ path: String, app: AppRef) -> Bool {
        let base = app.name.lowercased()
            .replacingOccurrences(of: #" \d{4}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #" \(beta\)$"#, with: "", options: .regularExpression)
        guard base.count >= 3 else { return false }
        return (path as NSString).pathComponents.dropLast().contains { $0.lowercased() == base }
    }

    /// Two points for a verified developer signature, one for an unverified
    /// one; two for strong evidence of the app, one for weaker; one for a
    /// launchd job.
    private static func confidence(of evidence: [Evidence]) -> Confidence {
        var points = 0
        for item in evidence {
            switch item {
            case let .signed(_, _, verified): points += verified == true ? 2 : 1
            case .launchdJob: points += 1
            default: break
            }
        }
        let strongest = evidence.map(\.appWeight).max() ?? 0
        points += strongest >= 60 ? 2 : (strongest > 0 ? 1 : 0)
        let level: Confidence = points >= 4 ? .high : (points >= 2 ? .medium : .low)
        // Code that no longer matches its signature is never trusted fully.
        let mismatched = evidence.contains {
            if case .signed(_, _, false?) = $0 { return true }
            return false
        }
        return mismatched ? min(level, .medium) : level
    }
}

// MARK: - Formatting

enum Bytes {
    static func text(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb < 1 { return bytes == 0 ? "—" : "<1 MB" }
        if mb < 1000 { return "\(Int(mb.rounded())) MB" }
        return String(format: "%.1f GB", mb / 1024)
    }
}
