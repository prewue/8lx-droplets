import Foundation

/// A made-up Mac for the harness and for Droppy Playground's demo setting:
/// open apps, helpers left behind by closed ones, a vendor's shared
/// services, things kept closed, terminal tools and servers. It never
/// changes on its own, and nothing here touches a real process.
enum DemoData {
    private static func job(_ label: String, keepAlive: Bool, runAtLoad: Bool = true) -> LaunchJob {
        LaunchJob(label: label, plistPath: nil, domain: .user, program: nil, keepAlive: keepAlive, runAtLoad: runAtLoad, associatedBundleIDs: [])
    }

    private static func signed(_ organization: String, _ team: String) -> Evidence {
        .signed(organization: organization, team: team, verified: true)
    }

    private static let adobe = signed("Adobe", "JQ525L2MZD")
    private static let google = signed("Google", "EQHXZ8M8AV")
    private static let logitech = signed("Logitech", "QED4VVPZWA")

    private static func process(
        _ pid: pid_t,
        _ name: String,
        _ mb: Double,
        _ kind: ProcessKind,
        label: String? = nil,
        keepAlive: Bool = false,
        privileged: Bool = false,
        menuBar: Bool = false,
        evidence: [Evidence] = [],
        confidence: Confidence = .high
    ) -> ProcessEntry {
        var reasons = evidence
        if let label { reasons.append(.launchdJob(label: label, keepAlive: keepAlive, runAtLoad: true)) }
        if privileged { reasons.append(.runsAs(user: "root")) }
        if menuBar { reasons.append(.menuBar) }
        return ProcessEntry(
            pid: pid,
            name: name,
            path: "/Library/Application Support/Demo/\(name)",
            memory: UInt64(mb * 1_048_576),
            kind: kind,
            label: label,
            keepAlive: keepAlive,
            isPrivileged: privileged,
            isMenuBar: menuBar,
            evidence: reasons,
            confidence: confidence
        )
    }

    static let groups: [AppGroup] = [
        // Open apps, the top of the list.
        AppGroup(
            id: "EQHXZ8M8AV|/Applications/Google Chrome.app",
            teamID: "EQHXZ8M8AV",
            name: "Google Chrome",
            organization: "Google",
            iconPath: "/Applications/Google Chrome.app",
            appPath: "/Applications/Google Chrome.app",
            runningApps: ["Google Chrome"],
            processes: [
                process(801, "Google Chrome", 486, .app, evidence: [google]),
                process(802, "Google Chrome Helper (Renderer)", 212, .bundled, evidence: [google, .insideBundle(app: "Google Chrome")]),
                process(803, "Google Chrome Helper (Renderer)", 188, .bundled, evidence: [google, .insideBundle(app: "Google Chrome")]),
                process(804, "Google Chrome Helper (Renderer)", 164, .bundled, evidence: [google, .insideBundle(app: "Google Chrome")]),
                process(805, "Google Chrome Helper (Renderer)", 97, .bundled, evidence: [google, .insideBundle(app: "Google Chrome")]),
                process(806, "Google Chrome Helper (GPU)", 236, .bundled, evidence: [google, .insideBundle(app: "Google Chrome")]),
                process(807, "Google Chrome Helper", 42, .bundled, evidence: [google, .insideBundle(app: "Google Chrome")]),
                process(808, "chrome_crashpad_handler", 6, .helper, evidence: [google, .startedBy("Google Chrome")]),
                process(809, "GoogleUpdater", 18, .agent, label: "com.google.GoogleUpdater.wake", keepAlive: false, evidence: [google])
            ],
            jobs: [job("com.google.GoogleUpdater.wake", keepAlive: false)],
            loadedLabels: ["com.google.GoogleUpdater.wake"]
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
                process(923, "Microsoft Word Helper", 22, .bundled, evidence: [.insideBundle(app: "Microsoft Word")]),
                process(924, "Microsoft AutoUpdate", 31, .agent, label: "com.microsoft.update.agent", keepAlive: true, evidence: [signed("Microsoft", "UBF8T346G9")])
            ],
            jobs: [job("com.microsoft.update.agent", keepAlive: true)],
            loadedLabels: ["com.microsoft.update.agent"]
        ),
        AppGroup(
            id: "8VBZ3948LU|/Applications/Droppy Playground.app",
            teamID: "8VBZ3948LU",
            name: "Droppy Playground",
            organization: "Droppy",
            iconPath: "/Applications/Droppy Playground.app",
            appPath: "/Applications/Droppy Playground.app",
            runningApps: ["Droppy Playground"],
            processes: [process(990, "Droppy Playground", 180, .app)],
            jobs: [],
            loadedLabels: [],
            isHost: true
        ),

        // Left behind: the app is closed, these kept running.
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
            id: "QED4VVPZWA|/Applications/logioptionsplus.app",
            teamID: "QED4VVPZWA",
            name: "Logi Options+",
            organization: "Logitech",
            iconPath: "/Applications/logioptionsplus.app",
            appPath: "/Applications/logioptionsplus.app",
            runningApps: [],
            processes: [
                process(941, "logioptionsplus_agent", 118, .agent, label: "com.logi.optionsplus", keepAlive: true, evidence: [logitech]),
                process(942, "Logi Options+ Driver Installer", 0, .agent, privileged: true, evidence: [logitech]),
                process(943, "logioptionsplus_updater", 24, .helper, evidence: [logitech, .startedBy("logioptionsplus_agent")])
            ],
            jobs: [job("com.logi.optionsplus", keepAlive: true)],
            loadedLabels: ["com.logi.optionsplus"]
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
                    signed("Figma", "T8RA8NE3B7"),
                    .pathMentions(app: "Figma"),
                    .vendorsOnlyApp("Figma")
                ])
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
            id: "terminal|Neovim",
            category: .terminal,
            name: "Neovim",
            subtitle: "2 sessions",
            symbol: "terminal",
            items: [
                item("s5", "shop-api", age: "3h", 48, pids: [3101, 3102]),
                item("s6", "dotfiles", age: "1d", 31, pids: [3110])
            ],
            job: nil,
            ports: [],
            help: "Neovim, running in 2 terminal sessions."
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
            id: "server|4120",
            category: .servers,
            name: "python manage.py runserver",
            age: "25m",
            subtitle: "shop-api:8000",
            symbol: "network",
            items: [
                item("p4", "python:8000", 86, pids: [4120], symbol: "play.circle"),
                item("p5", "python", 64, pids: [4133], symbol: "arrow.turn.down.right")
            ],
            job: nil,
            ports: [8000],
            help: "$ python manage.py runserver"
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
        ),
        TaskGroup(
            id: "server|5530",
            category: .servers,
            name: "caffeinate -dims",
            age: "4h",
            subtitle: "Started by Terminal",
            symbol: "gearshape.2",
            items: [item("p6", "caffeinate", 1, pids: [5530], symbol: "play.circle")],
            job: nil,
            ports: [],
            help: "$ caffeinate -dims"
        )
    ]

    static let state = KillTreeState(
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
            ),
            ClosedGroup(
                id: "9BNSXJN65R|/Applications/Docker.app",
                name: "Docker",
                iconPath: "/Applications/Docker.app",
                jobs: [],
                persisted: true,
                closedAt: Date().addingTimeInterval(-3 * 3600),
                processCount: 7,
                freedMemory: 1_900 * 1_048_576
            ),
            ClosedGroup(
                id: "server|homebrew.mxcl.redis",
                name: "redis",
                iconPath: nil,
                jobs: [StoppedJob(job: job("homebrew.mxcl.redis", keepAlive: true), wasLoaded: true)],
                persisted: true,
                closedAt: Date().addingTimeInterval(-50 * 60),
                processCount: 1,
                freedMemory: 12 * 1_048_576
            )
        ],
        journal: [
            JournalEntry(date: Date().addingTimeInterval(-60), kind: .reclosed, text: "ZoomAutoUpdater started again and was closed again."),
            JournalEntry(date: Date().addingTimeInterval(-25 * 60), kind: .closed, text: "Zoom: 3 processes closed, 2 jobs stopped."),
            JournalEntry(date: Date().addingTimeInterval(-50 * 60), kind: .closed, text: "redis: 1 process ended, launchd job stopped."),
            JournalEntry(date: Date().addingTimeInterval(-3 * 3600), kind: .closed, text: "Docker: 7 processes closed, 1 job stopped.")
        ]
    )
}
