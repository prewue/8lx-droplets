import Darwin
import Foundation

/// One closable unit inside a task group: a terminal session, or the same
/// process several times in a server's tree.
struct TaskItem: Identifiable, Sendable {
    let id: String
    let title: String
    /// How long it has run, shown beside the title: "1h".
    var age: String?
    /// A count, "×4", when it is the same process several times.
    let detail: String
    let symbol: String
    let memory: UInt64
    /// pid → executable, so a recycled pid is never hit.
    let processes: [pid_t: String]
    let help: String

    var count: Int { processes.count }
}

/// A tool with its sessions, or a server with its processes.
struct TaskGroup: Identifiable, Sendable {
    let id: String
    let category: Category
    let name: String
    /// How long it has run, shown beside the name.
    var age: String?
    /// The line under the name: "8 sessions", "tg.page.w2:3100".
    let subtitle: String
    /// Where it comes from, as badges: "Homebrew".
    var badges: [String] = []
    let symbol: String
    let items: [TaskItem]
    /// The launchd job that runs it (a Homebrew service): stopped first, so
    /// launchd does not start it again, and given back by Restore.
    let job: LaunchJob?
    let ports: [Int]
    let help: String

    var memory: UInt64 { items.reduce(0) { $0 + $1.memory } }
    var isExpandable: Bool { items.count > 1 }
    var processes: [pid_t: String] {
        items.reduce(into: [:]) { result, item in result.merge(item.processes) { first, _ in first } }
    }
}

enum TaskBuilder {
    /// Names people know tools by, keyed by the executable.
    private static let knownTools: [String: String] = [
        "claude": "Claude Code", "codex": "Codex", "gemini": "Gemini CLI", "aider": "Aider",
        "opencode": "OpenCode", "cursor-agent": "Cursor Agent", "goose": "Goose", "amp": "Amp",
        "vim": "Vim", "nvim": "Neovim", "htop": "htop", "btop": "btop", "ssh": "SSH", "tmux": "tmux"
    ]

    static func build(
        hidden: [HiddenProcess],
        byPID: [pid_t: RawProcess],
        jobByPID: [pid_t: String],
        jobsByLabel: [String: LaunchJob],
        ports: [pid_t: [Int]]
    ) -> [TaskGroup] {
        let me = getuid()
        let members = hidden.filter { $0.reason != .host && byPID[$0.pid]?.uid == me }

        /// The terminal a process runs in, its own or its nearest ancestor's.
        func tty(of pid: pid_t) -> String? {
            var current = pid
            for _ in 0..<16 {
                guard let process = byPID[current] else { return nil }
                if let tty = process.tty { return tty }
                current = process.ppid
                if current <= 1 { return nil }
            }
            return nil
        }

        var terminal: [HiddenProcess] = []
        var servers: [HiddenProcess] = []
        for member in members {
            if tty(of: member.pid) != nil { terminal.append(member) } else { servers.append(member) }
        }

        // A session owns everything under it, Apple's tools too
        // (sourcekit-lsp under Claude Code): they end with it.
        let everyone = Set(byPID.keys)

        func descendants(of root: pid_t, within set: Set<pid_t>) -> [pid_t] {
            var result = [root]
            var frontier = [root]
            while let next = frontier.popLast() {
                for pid in set where byPID[pid]?.ppid == next && !result.contains(pid) {
                    result.append(pid)
                    frontier.append(pid)
                }
            }
            return result
        }

        func roots(of set: Set<pid_t>) -> [pid_t] {
            set.filter { pid in !(byPID[pid].map { set.contains($0.ppid) } ?? false) }.sorted()
        }

        var groups: [TaskGroup] = []

        // Terminal: one session per root process of a terminal, sessions of
        // the same tool together.
        let terminalSet = Set(terminal.map(\.pid))
        var sessionsByTool: [String: [TaskItem]] = [:]
        for root in roots(of: terminalSet) {
            guard let raw = byPID[root] else { continue }
            let pids = descendants(of: root, within: everyone)
            let tool = toolName(for: raw)
            let cwd = ProcessScanner.workingDirectory(of: root)
            let command = ProcessScanner.arguments(of: root).joined(separator: " ")
            let memory = pids.compactMap { byPID[$0]?.memory }.reduce(0, +)
            let ttyName = tty(of: root) ?? "terminal"
            let title = cwd.flatMap(projectName(from:)) ?? "Session in \(ttyName)"
            let names = pids.compactMap { byPID[$0].map { BundlePath.displayName(for: $0.path) } }
            let help = [
                "\(tool) in \(ttyName), \(pids.count) process\(pids.count == 1 ? "" : "es")",
                command.isEmpty ? nil : "$ " + command,
                cwd.map { "in \($0)" },
                "",
                "Processes: " + summarize(names),
                "",
                "Closing ends this session: SIGTERM, then SIGKILL after 2.5 s. The terminal tab stays; whatever the tool had not saved is lost."
            ].compactMap { $0 }.joined(separator: "\n")
            sessionsByTool[tool, default: []].append(TaskItem(
                id: "session|\(ttyName)|\(root)",
                title: title,
                age: raw.startedAt.map(age),
                detail: "",
                symbol: "terminal",
                memory: memory,
                processes: Dictionary(uniqueKeysWithValues: pids.compactMap { pid in byPID[pid].map { (pid, $0.path) } }),
                help: help
            ))
        }
        for (tool, sessions) in sessionsByTool {
            let sorted = sessions.sorted { $0.memory > $1.memory }
            let processCount = sorted.reduce(0) { $0 + $1.count }
            groups.append(TaskGroup(
                id: "terminal|\(tool)",
                category: .terminal,
                name: tool,
                age: sorted.count == 1 ? sorted[0].age : nil,
                // One session says where it runs; several say how many.
                subtitle: sorted.count == 1 ? sorted[0].title : "\(sorted.count) sessions",
                symbol: "terminal",
                items: sorted,
                job: nil,
                ports: [],
                help: "\(tool), running in \(sorted.count) terminal session\(sorted.count == 1 ? "" : "s") with \(processCount) process\(processCount == 1 ? "" : "es") in all. Open it to close one session; the × closes them all."
            ))
        }

        // Servers: one per root, its whole tree with it.
        let serverSet = Set(servers.map(\.pid))
        for root in roots(of: serverSet) {
            guard let raw = byPID[root] else { continue }
            let pids = descendants(of: root, within: serverSet)
            let label = jobByPID[root]
            let job = label.flatMap { jobsByLabel[$0] }
            let arguments = ProcessScanner.arguments(of: root)
            let cwd = ProcessScanner.workingDirectory(of: root)
            let treePorts = Array(Set(pids.flatMap { ports[$0] ?? [] })).sorted()
            let reason = hidden.first { $0.pid == root }?.reason

            var name = arguments.prefix(3).joined(separator: " ")
            var origin: String?
            if let label {
                for prefix in ["homebrew.mxcl.", "sh.brew."] where label.hasPrefix(prefix) {
                    name = String(label.dropFirst(prefix.count))
                    origin = "Homebrew"
                }
                if origin == nil { origin = "launchd" }
            }
            if name.isEmpty { name = BundlePath.displayName(for: raw.path) }
            if name.count > 34 { name = String(name.prefix(33)) + "…" }

            // "tg.page.w2:3100", "localhost:5432", or the project alone.
            let project = label == nil ? cwd.flatMap(projectName(from:)) : nil
            let host = project ?? (treePorts.isEmpty ? nil : "localhost")
            var address = host.map { host in
                treePorts.isEmpty ? host : host + ":" + treePorts.prefix(2).map(String.init).joined(separator: ", :")
            } ?? ""
            if address.isEmpty, case let .foreignParent(parent)? = reason { address = "Started by \(parent)" }
            if address.isEmpty { address = "No port" }

            // The tree's processes, the same ones together.
            var order: [String] = []
            var clusters: [String: [pid_t]] = [:]
            for pid in pids {
                guard let process = byPID[pid] else { continue }
                var title = pid == root ? (arguments.first ?? BundlePath.displayName(for: process.path)) : BundlePath.displayName(for: process.path)
                if title.count > 40 { title = String(title.prefix(39)) + "…" }
                if clusters[title] == nil { order.append(title) }
                clusters[title, default: []].append(pid)
            }
            let items = order.map { title -> TaskItem in
                let clusterPIDs = clusters[title]!
                let memory = clusterPIDs.compactMap { byPID[$0]?.memory }.reduce(0, +)
                let path = byPID[clusterPIDs[0]]?.path ?? ""
                let itemPorts = Array(Set(clusterPIDs.flatMap { ports[$0] ?? [] })).sorted()
                return TaskItem(
                    id: "proc|\(root)|\(title)",
                    title: itemPorts.isEmpty ? title : title + ":" + itemPorts.map(String.init).joined(separator: ", :"),
                    detail: clusterPIDs.count > 1 ? "×\(clusterPIDs.count)" : "",
                    symbol: clusterPIDs.contains(root) ? "play.circle" : "arrow.turn.down.right",
                    memory: memory,
                    processes: Dictionary(uniqueKeysWithValues: clusterPIDs.compactMap { pid in byPID[pid].map { (pid, $0.path) } }),
                    help: "\(title)\n\(path)\npid " + clusterPIDs.map(String.init).joined(separator: ", ")
                )
            }

            var help = ["$ " + (arguments.isEmpty ? raw.path : arguments.joined(separator: " "))]
            if let cwd { help.append("in \(cwd)") }
            if let label { help.append("launchd job \(label)" + (job?.keepAlive == true ? ", restarts when it exits" : "")) }
            if !treePorts.isEmpty { help.append("Listens on " + treePorts.map { ":\($0)" }.joined(separator: ", ")) }
            if let reason { help += ["", reason.explanation] }
            help += ["", job != nil
                ? "Closing takes the job out of launchd first, so it stays stopped, then ends the tree. Restore starts it again."
                : "Closing ends the whole tree: SIGTERM, then SIGKILL after 2.5 s. Nothing starts it again."]

            groups.append(TaskGroup(
                id: "server|\(label ?? "\(root)")",
                category: .servers,
                name: name,
                age: raw.startedAt.map(age),
                subtitle: address,
                badges: origin.map { [$0 == "launchd" ? "Launchd" : $0] } ?? [],
                symbol: job != nil ? "server.rack" : (treePorts.isEmpty ? "gearshape.2" : "network"),
                items: items,
                job: job?.domain == .user ? job : nil,
                ports: treePorts,
                help: help.joined(separator: "\n")
            ))
        }

        return groups.sorted { ($1.memory, $0.name) < ($0.memory, $1.name) }
    }

    /// "claude 2.1.310" → "Claude Code"; a runtime running a script is named
    /// after the script.
    static func toolName(for process: RawProcess) -> String {
        var base = BundlePath.displayName(for: process.path)
        if let space = base.firstIndex(of: " "), base[base.index(after: space)...].allSatisfy({ $0.isNumber || $0 == "." }) {
            base = String(base[..<space])
        }
        if BundlePath.isRuntime(process.path) {
            let arguments = ProcessScanner.arguments(of: process.pid)
            if let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                base = ((script as NSString).lastPathComponent as NSString).deletingPathExtension
            }
        }
        return knownTools[base.lowercased()] ?? base
    }

    /// The folder a person would call the project:
    /// ".../tg.page.w2/.maestri/roles/51110ddf-…" → "tg.page.w2".
    static func projectName(from path: String) -> String? {
        let skipped: Set<String> = ["roles", "workspaces", "worktrees", "sessions", "tmp", "temp", "src", "bin"]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path != home else { return "~" }
        for component in (path as NSString).pathComponents.reversed() {
            if component == "/" || component.hasPrefix(".") || skipped.contains(component.lowercased()) { continue }
            if UUID(uuidString: component) != nil { continue }
            if component.count >= 24, component.allSatisfy({ $0.isHexDigit || $0 == "-" }) { continue }
            if ["Users", (home as NSString).lastPathComponent].contains(component) { return nil }
            return component
        }
        return nil
    }

    /// "12m", "3h", "2d": how long it has been running.
    static func age(_ date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 60 { return "\(max(minutes, 1))m" }
        if minutes < 60 * 24 { return "\(minutes / 60)h" }
        return "\(minutes / (60 * 24))d"
    }

    /// "claude, node ×3, caffeinate".
    private static func summarize(_ names: [String]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for name in names {
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }.joined(separator: ", ")
    }
}
