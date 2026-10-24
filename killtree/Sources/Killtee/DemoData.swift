import Foundation

/// What the harness shows: a Mac with Adobe, Figma and Microsoft leftovers.
/// Nothing here touches a real process.
enum DemoData {
    private static func job(_ label: String, keepAlive: Bool, runAtLoad: Bool = true) -> LaunchJob {
        LaunchJob(label: label, plistPath: nil, domain: .user, program: nil, keepAlive: keepAlive, runAtLoad: runAtLoad, associatedBundleIDs: [])
    }

    private static let adobe = Evidence.signed(organization: "Adobe", team: "JQ525L2MZD", verified: true)

    private static func process(
        _ pid: pid_t,
        _ name: String,
        _ mb: Double,
        _ kind: ProcessKind,
        label: String? = nil,
        keepAlive: Bool = false,
        privileged: Bool = false,
        evidence: [Evidence] = [],
        confidence: Confidence = .high
    ) -> ProcessEntry {
        var reasons = evidence
        if let label { reasons.append(.launchdJob(label: label, keepAlive: keepAlive, runAtLoad: true)) }
        if privileged { reasons.append(.runsAs(user: "root")) }
        return ProcessEntry(
            pid: pid,
            name: name,
            path: "/Library/Application Support/Demo/\(name)",
            memory: UInt64(mb * 1_048_576),
            kind: kind,
            label: label,
            keepAlive: keepAlive,
            isPrivileged: privileged,
            evidence: reasons,
            confidence: confidence
        )
    }

    static let groups: [AppGroup] = [
        AppGroup(
            id: "JQ525L2MZD|shared",
            teamID: "JQ525L2MZD",
            name: "Adobe services",
            organization: "Adobe",
            iconPath: "/Applications/Adobe Illustrator 2024/Adobe Illustrator.app",
            appPath: nil,
            runningApps: [],
            processes: [
                process(901, "CCXProcess", 212, .agent, label: "com.adobe.ccxprocess", keepAlive: true, evidence: [adobe]),
                process(902, "Creative Cloud Helper", 168, .helper, evidence: [adobe]),
                process(903, "CoreSync", 121, .agent, label: "com.adobe.CoreSync", keepAlive: true, evidence: [adobe]),
                process(904, "Adobe Desktop Service", 96, .helper, evidence: [adobe]),
                process(907, "node", 41, .helper, evidence: [adobe, .startedBy("CCXProcess")]),
                process(908, "node", 38, .helper, evidence: [adobe, .startedBy("CCXProcess")]),
                process(909, "node", 35, .helper, evidence: [adobe, .startedBy("CCXProcess")]),
                process(906, "AGSService", 0, .agent, privileged: true, evidence: [.signed(organization: "Adobe", team: "JQ525L2MZD", verified: nil)], confidence: .low)
            ],
            jobs: [job("com.adobe.ccxprocess", keepAlive: true), job("com.adobe.CoreSync", keepAlive: true)],
            loadedLabels: ["com.adobe.ccxprocess", "com.adobe.CoreSync"]
        ),
        AppGroup(
            id: "T8RA8NE3B7|/Applications/Figma.app",
            teamID: "T8RA8NE3B7",
            name: "Figma",
            organization: "Figma",
            iconPath: "/Applications/Figma.app",
            appPath: "/Applications/Figma.app",
            runningApps: [],
            processes: [
                process(911, "FigmaAgent", 84, .agent, evidence: [
                    .signed(organization: "Figma", team: "T8RA8NE3B7", verified: true),
                    .pathMentions(app: "Figma"),
                    .vendorsOnlyApp("Figma")
                ])
            ],
            jobs: [],
            loadedLabels: []
        ),
        AppGroup(
            id: "UBF8T346G9|/Applications/Microsoft Word.app",
            teamID: "UBF8T346G9",
            name: "Microsoft Word",
            organization: "Microsoft",
            iconPath: "/Applications/Microsoft Word.app",
            appPath: "/Applications/Microsoft Word.app",
            runningApps: ["Microsoft Word"],
            processes: [
                process(921, "Microsoft Word", 412, .app),
                process(923, "Microsoft Word Helper", 22, .helper, evidence: [.insideBundle(app: "Microsoft Word")])
            ],
            jobs: [],
            loadedLabels: []
        ),
        AppGroup(
            id: "VB5E2TV963|shared",
            teamID: "VB5E2TV963",
            name: "Oracle America",
            organization: "Oracle America",
            iconPath: nil,
            appPath: nil,
            runningApps: [],
            processes: [],
            jobs: [job("com.oracle.java.Java-Updater", keepAlive: false)],
            loadedLabels: ["com.oracle.java.Java-Updater"]
        )
    ]

    static let hidden: [HiddenProcess] = [
        HiddenProcess(pid: 1026, name: "claude 2.1.310", path: "~/.local/share/claude/versions/2.1.310", memory: 2_600 * 1_048_576, reason: .terminal),
        HiddenProcess(pid: 3513, name: "node", path: "/usr/local/bin/node", memory: 640 * 1_048_576, reason: .runtime),
        HiddenProcess(pid: 1120, name: "postgres", path: "/opt/homebrew/opt/postgresql@18/bin/postgres", memory: 240 * 1_048_576, reason: .unsigned, label: "sh.brew.postgresql@18")
    ]

    private static func item(_ id: String, _ title: String, age: String? = nil, count: String = "", _ mb: Double, pids: [pid_t], symbol: String = "terminal") -> TaskItem {
        TaskItem(
            id: id,
            title: title,
            age: age,
            detail: count,
            symbol: symbol,
            memory: UInt64(mb * 1_048_576),
            processes: Dictionary(uniqueKeysWithValues: pids.map { ($0, "/demo/\($0)") }),
            help: title
        )
    }

    static let tasks: [TaskGroup] = [
        TaskGroup(
            id: "terminal|Claude Code",
            category: .terminal,
            name: "Claude Code",
            subtitle: "3 sessions",
            symbol: "terminal",
            items: [
                item("s1", "tg.page.w2", age: "1h", 583, pids: [2019, 2139]),
                item("s2", "tg.page.work", age: "1h", 571, pids: [2024, 2174]),
                item("s3", "Session in ttys004", age: "2h", 699, pids: [1710, 1804])
            ],
            job: nil,
            ports: [],
            help: "Claude Code, running in 3 terminal sessions."
        ),
        TaskGroup(
            id: "terminal|Codex",
            category: .terminal,
            name: "Codex",
            age: "5m",
            subtitle: "droppykit",
            symbol: "terminal",
            items: [item("s4", "droppykit", age: "5m", 96, pids: [3001])],
            job: nil,
            ports: [],
            help: "Codex"
        ),
        TaskGroup(
            id: "server|3457",
            category: .servers,
            name: "npm run dev",
            age: "1h",
            subtitle: "tg.page.w2:3100",
            symbol: "network",
            items: [
                item("p1", "npm run dev", 22, pids: [3457], symbol: "play.circle"),
                item("p2", "node:3100", count: "×4", 4_900, pids: [3513, 3514, 3604, 3607], symbol: "arrow.turn.down.right")
            ],
            job: nil,
            ports: [3100],
            help: "$ npm run dev"
        ),
        TaskGroup(
            id: "server|sh.brew.postgresql@18",
            category: .servers,
            name: "postgresql@18",
            age: "1h",
            subtitle: "localhost:5432",
            badges: ["Homebrew"],
            symbol: "server.rack",
            items: [item("p3", "postgres:5432", count: "×26", 216, pids: [1120], symbol: "play.circle")],
            job: job("sh.brew.postgresql@18", keepAlive: true),
            ports: [5432],
            help: "$ postgres -D /opt/homebrew/var/postgresql@18"
        )
    ]

    static let state = KillteeState(
        closed: [
            ClosedGroup(
                id: "BJ4HAAB9B3|/Applications/zoom.us.app",
                name: "Zoom",
                iconPath: "/Applications/zoom.us.app",
                jobs: [],
                persisted: true,
                closedAt: Date().addingTimeInterval(-25 * 60),
                processCount: 3,
                freedMemory: 140 * 1_048_576,
                reclosed: 2
            )
        ],
        journal: [
            JournalEntry(date: Date().addingTimeInterval(-60), kind: .reclosed, text: "ZoomAutoUpdater started again and was closed again."),
            JournalEntry(date: Date().addingTimeInterval(-25 * 60), kind: .closed, text: "Zoom: 3 processes closed, 2 jobs stopped.")
        ]
    )
}
