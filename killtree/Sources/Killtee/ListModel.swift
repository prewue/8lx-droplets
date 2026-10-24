import Darwin
import Foundation

enum ListSection: String, Sendable {
    case closed, stopped

    var title: String {
        switch self {
        case .closed: return "Kept closed"
        case .stopped: return "Stopped"
        }
    }

    var help: String {
        switch self {
        case .closed: return "Closed by KillTee. Anything of them that starts again is closed again until you open the app."
        case .stopped: return "Services KillTee took out of launchd. Restore loads them again."
        }
    }
}

/// One row of the shelf list. An open group is one row: its header and its
/// children drawn together in one glass block.
enum ListRow: Identifiable {
    case section(ListSection, count: Int, memory: UInt64)
    /// An app group, with its processes when it is open.
    case group(AppGroup, children: [ProcessCluster]?)
    case closed(ClosedGroup)
    /// A terminal tool or a server, open or not.
    case task(TaskGroup, isOpen: Bool)

    var id: String {
        switch self {
        case .section(let section, _, _): return "section.\(section.rawValue)"
        case .group(let group, _): return "group.\(group.id)"
        case .closed(let closed): return "closed.\(closed.id)"
        case .task(let task, _): return "task.\(task.id)"
        }
    }

    var height: CGFloat {
        switch self {
        case .section: return KillteeDroplet.sectionHeaderHeight
        case .closed: return KillteeDroplet.groupRowHeight
        case let .group(_, children):
            return KillteeDroplet.blockHeight(children: children?.count)
        case let .task(task, isOpen):
            return KillteeDroplet.blockHeight(children: isOpen ? task.items.count : nil)
        }
    }
}

/// Processes that are the same thing several times (twelve renderers, eight
/// workers), shown as one row with a count.
struct ProcessCluster: Identifiable, Sendable {
    let id: String
    let entries: [ProcessEntry]

    var first: ProcessEntry { entries[0] }
    var count: Int { entries.count }
    var memory: UInt64 { entries.reduce(0) { $0 + $1.memory } }
    var confidence: Confidence { entries.map(\.confidence).min() ?? .medium }

    static func clusters(of processes: [ProcessEntry]) -> [ProcessCluster] {
        var order: [String] = []
        var byKey: [String: [ProcessEntry]] = [:]
        for process in processes {
            let key = "\(process.name)|\(process.kind.rawValue)|\(process.isPrivileged)|\(process.keepAlive)|\(process.isMenuBar)"
            if byKey[key] == nil { order.append(key) }
            byKey[key, default: []].append(process)
        }
        return order.map { ProcessCluster(id: $0, entries: byKey[$0]!) }
    }

    /// What it is, why it is listed here, and what closing does to it.
    var help: String {
        var lines: [String] = []
        lines.append(count > 1 ? "\(first.name) ×\(count)" : first.name)
        lines.append(first.isMenuBar ? "A menu bar app started by the vendor's helpers." : first.kind.title)
        lines.append("")
        lines.append("Why it is here:")
        lines += first.evidence.map { "• " + $0.text }
        lines.append("Confidence: \(confidence.title)")
        lines.append("")
        lines.append(closingNote)
        lines.append("")
        lines.append(first.path)
        lines.append(count > 1 ? "pids " + entries.map { String($0.pid) }.joined(separator: ", ") : "pid \(first.pid)")
        return lines.joined(separator: "\n")
    }

    private var closingNote: String {
        if first.kind == .system { return "Closing leaves it: macOS would start it again at once." }
        if first.isPrivileged { return "Closing needs “Also stop system services” and an administrator password." }
        if let label = first.label, !label.hasPrefix("application.") {
            return "Closing takes \(label) out of launchd first, so it cannot restart, then ends it."
        }
        if first.kind == .app { return "Closing quits it the normal way; unsaved work stops the close." }
        return "Closing ends it: SIGTERM, then SIGKILL if it has not exited after 2.5 s."
    }
}

extension AppGroup {
    /// The row's tooltip: what the group is and how it was put together.
    var help: String {
        var lines: [String] = []
        if let appPath {
            lines.append("\(name), \(appPath)")
            lines.append("Processes tied to this app by its signature, bundle, launchd jobs, parents and identifiers. Hover a process for its own evidence.")
        } else {
            lines.append(name)
            lines.append("Signed by \(organization ?? "this developer"), but part of none of its apps in particular: shared services every one of its apps uses.")
        }
        if !isAppRunning, !processes.isEmpty {
            lines.append("")
            lines.append("The app is closed; these kept running.")
        }
        let startup = startupJobs.count
        if startup > 0 {
            lines.append("")
            lines.append("\(startup) launchd job\(startup == 1 ? "" : "s") start\(startup == 1 ? "s" : "") at login: " + startupJobs.map(\.label).joined(separator: ", "))
        }
        if teamID.hasPrefix("adhoc:") {
            lines.append("")
            lines.append("This app has no developer signature; it is matched by its bundle id.")
        } else {
            lines.append("")
            lines.append("Team ID \(teamID)")
        }
        return lines.joined(separator: "\n")
    }
}
