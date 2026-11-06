//
//  KillTreeDroplet.swift
//  KillTree
//

import AppKit
import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(KillTreePrincipal)
public final class KillTreePrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { KillTreeDroplet() }
}

public enum KillTreeScreen: Equatable {
    case welcome
    case category(Category)
}

/// What a row asks to be confirmed before it is closed.
public enum ConfirmTarget: Equatable {
    /// An app or a vendor's services.
    case group(String)
    /// A terminal tool with all its sessions, or a server with its tree.
    case task(String)
    /// One session of a tool, or one kind of process in a server.
    case item(task: String, item: String)
    /// The same process of an app group, one or several times.
    case cluster(group: String, cluster: String)
}

/// K*llTree: an app's whole family of processes, closed in one go and kept
/// closed until the app is opened again.
@MainActor
public final class KillTreeDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal `DroppyDropletID` in the bundle's Info.plist and `id` in
    /// droplet.json. The loader refuses the bundle if the three disagree.
    public nonisolated static let id: DropletID = "killtree"

    static let widgetID: ShelfWidgetID = "killtree"

    private(set) var host: DropletHost?

    @Published public private(set) var screen: KillTreeScreen = .category(.apps)
    @Published private(set) var groups: [AppGroup] = []
    @Published private(set) var hidden: [HiddenProcess] = []
    @Published private(set) var tasks: [TaskGroup] = []
    /// The list the confirmation screen goes back to.
    private(set) var lastCategory: Category = .apps
    @Published private(set) var state = KillTreeState()
    @Published var expanded: Set<String> = []
    /// Vendors being closed or brought back right now, with what is happening.
    @Published private(set) var working: [String: String] = [:]
    @Published private(set) var hasScanned = false
    /// The refresh button: spinning while a scan the person asked for runs,
    /// done once that scan has really finished.
    @Published private(set) var refreshPhase: RefreshPhase = .idle
    /// The row whose close button was pressed once: it shows Kill and a way
    /// back until either is chosen.
    @Published private(set) var confirming: ConfirmTarget?
    /// Mounted beside other widgets, as far as the last mount said.
    private(set) var isPaired = false
    /// The corner disc has opened into its panel.
    @Published private(set) var isToolsOpen = false
    let power = SleepControl()
    /// When something was last ended here: the rescan after it takes the
    /// ended rows out, and takes them out animated.
    private var endedAt = Date.distantPast

    let scanner = ProcessScanner()
    private var installed: [InstalledApp] = []
    private var installedReadAt: Date = .distantPast
    private var isScanning = false
    private var rescanRequested = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var visibleWidgets = 0
    /// Showing the made-up Mac from `DemoData`: the harness always, Droppy
    /// Playground when its settings say so. Nothing real is scanned, closed
    /// or saved.
    private(set) var isDemo = false
    /// Demo servers closed with a launchd job, kept to come back on Restore.
    private var demoStash: [String: TaskGroup] = [:]
    /// Scans started so far, and the one the refresh button waits for.
    private var scansStarted = 0
    private var refreshAwaits: Int?

    /// Background processes the guard sent SIGTERM, to follow up with SIGKILL.
    private var terminating: [pid_t: (path: String, at: Date)] = [:]
    /// When the guard closed each path again, to notice one it cannot hold.
    private var reclosedAt: [String: [Date]] = [:]
    private var givenUp: Set<String> = []
    /// Vendors whose Restore was refused its password: opening the app does
    /// not ask again at every scan. The Restore button still does.
    private var restoreRefused: Set<String> = []
    /// Scans started before something closed saw it still running.
    private var acceptedScan = 0
    /// Kept past `deactivate()`: a close still running has to save its record
    /// where the next activation will find it.
    private var containerDirectory: URL?
    /// Something for the next save: a guard pass that changed nothing writes nothing.
    private var stateChanged = false

    private let layoutSubject = PassthroughSubject<ShelfWidgetID, Never>()
    private var lastHeight: CGFloat = 0

    private enum Keys {
        static let hasSeenWelcome = "hasSeenWelcome"
        static let persists = "persistsAcrossRestart"
        static let autoRestore = "autoRestore"
        static let guards = "guardsClosed"
        static let includesSystem = "includesSystem"
        static let showsAll = "showsAll"
        static let showsHUD = "showsHUD"
        static let demoData = "demoData"
        static let includesServices = "stopAllIncludesServices"
        static let isPaired = "lastMountedPaired"
    }

    // MARK: Lifecycle

    public func activate(host: DropletHost) throws {
        self.host = host
        containerDirectory = host.environment.containerDirectory
        isPaired = preference(Keys.isPaired, default: false)
        screen = hasSeenWelcome ? .category(.apps) : .welcome
        if host.environment.isHarness {
            loadDemo()
            // The shots show the list with one vendor open; the welcome
            // screen was checked on its own.
            screen = .category(.apps)
            host.log.info("K*llTree activated with demo data")
            return
        }
        if offersDemo, preference(Keys.demoData, default: false) {
            loadDemo()
            host.log.info("K*llTree activated with demo data, from its settings")
            return
        }
        startLive()
    }

    /// Droppy Playground and the harness offer the made-up Mac, for trying
    /// the interface; Droppy itself never does.
    var offersDemo: Bool {
        Bundle.main.bundleIdentifier == "iordv.DroppyPlayground" || host?.environment.isHarness == true
    }

    /// The made-up Mac, as it starts: a static list that never rescans.
    private func loadDemo() {
        stopLive()
        isDemo = true
        power.enterDemo()
        groups = DemoData.groups
        hidden = DemoData.hidden
        tasks = DemoData.tasks
        state = DemoData.state
        demoStash = [:]
        working = [:]
        hasScanned = true
        expanded = ["terminal|Claude Code", "server|3457", "JQ525L2MZD|shared"]
        publishLayoutChange()
    }

    /// The real Mac: its saved state, scanned now and every few seconds.
    private func startLive() {
        isDemo = false
        groups = []
        hidden = []
        tasks = []
        working = [:]
        expanded = []
        hasScanned = false
        state = KillTreeState()
        // Left on by an earlier run: it keeps the Mac awake with the lid
        // closed, so it is said out loud, not only shown on the disc.
        power.enterLive { [weak self] lidClosed in
            guard lidClosed, let self else { return }
            self.presentStrip(symbol: "laptopcomputer", tint: .orange, title: "Lid closed mode", detail: "On", always: true)
        }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            })
        }
        let url = stateURL
        Task { [weak self] in
            let saved = await BlockingWork.run { KillTreeState.load(from: url) }
            guard let self, !self.isDemo, self.host != nil else { return }
            self.state = saved
            self.updateTimer()
            self.refresh()
            self.host?.log.info("K*llTree activated, \(saved.closed.count) closed")
        }
    }

    /// Ticks only while there is something to scan for, and otherwise costs
    /// nothing: not even a wake-up.
    private func updateTimer() {
        guard !isDemo, host != nil, needsScanning else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Someone is looking at the widget, or something closed has to be watched
    /// for: its app opening, or its helpers coming back.
    private var needsScanning: Bool {
        visibleWidgets > 0 || (!state.closed.isEmpty && (guardsClosed || autoRestore))
    }

    private func stopLive() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
    }

    public func deactivate() {
        stopLive()
        power.stop()
        Launchctl.cancelRunning()
        isToolsOpen = false
        host = nil
    }

    /// Lid Closed Mode outlives the droplet, and nothing could turn it off
    /// once the droplet is gone: it has to be off before the droplet goes.
    public func prepareForRemoval() -> Bool {
        // As last read: this cannot wait for a tool. The settings page reads it
        // on appearing, and demo data does not hide it.
        // So does the system rule: only K*llTree's settings can take it away.
        guard power.systemLidClosed || power.skipsPassword else { return true }
        let title = power.systemLidClosed ? "Turn off lid closed mode" : "Turn off the password rule"
        presentStrip(symbol: "laptopcomputer", tint: .orange, title: title, detail: "First", always: true)
        host?.feedback.play(.failure)
        return false
    }

    /// Switches between the made-up Mac and the real one.
    func setDemo(_ on: Bool) {
        host?.preferences.setValue(on, forKey: Keys.demoData)
        if on { loadDemo() } else { startLive() }
        objectWillChange.send()
    }

    /// Back to the made-up Mac as it was before anything was closed.
    func resetDemo() {
        guard isDemo else { return }
        loadDemo()
    }

    private var stateURL: URL {
        (containerDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("state.json")
    }

    private func save() {
        stateChanged = false
        updateTimer()
        guard !isDemo else { return }
        let state = state
        let url = stateURL
        BlockingWork.write { state.save(to: url) }
    }

    // MARK: Scanning

    /// Scans while someone looks at the widget, and while there is a closed
    /// vendor to guard. Otherwise K*llTree costs nothing.
    private func tick() {
        if visibleWidgets > 0 { power.refresh() }
        guard needsScanning else { return }
        refresh()
    }

    func widgetAppeared() {
        visibleWidgets += 1
        updateTimer()
        power.refresh()
        refresh()
    }

    func widgetDisappeared() {
        visibleWidgets = max(0, visibleWidgets - 1)
        updateTimer()
        // Nothing waits to be confirmed on a shelf that is closed.
        confirming = nil
        if visibleWidgets == 0 { setToolsOpen(false, animated: false) }
    }

    public func refresh() {
        guard !isDemo, host != nil else { return }
        guard !isScanning else {
            rescanRequested = true
            return
        }
        isScanning = true
        scansStarted += 1
        let scan = scansStarted
        let scanner = scanner
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited }
            .map {
                RunningApp(
                    pid: $0.processIdentifier,
                    name: $0.localizedName ?? "App",
                    bundlePath: $0.bundleURL?.path,
                    isMenuBar: $0.activationPolicy == .accessory
                )
            }
        let rereadsApps = Date().timeIntervalSince(installedReadAt) > 600
        let knownApps = installed
        let hostPath = Bundle.main.bundlePath
        let ownPID = getpid()
        Task { [weak self] in
            let (apps, result) = await BlockingWork.run { () -> ([InstalledApp], ScanResult) in
            let apps = rereadsApps ? AppDirectory.read(scanner: scanner) : knownApps
            // Droppy's own team: closing Droppy from inside Droppy ends badly.
            let excluded = Set([scanner.signature(at: hostPath)?.teamID].compactMap { $0 })
            let processes = scanner.scan()
            let bundles = Set(apps.map(\.path) + running.compactMap(\.bundlePath))
            let catalog = LaunchCatalog.read(appBundles: Array(bundles))
            // Apple's window apps, found by the signature of their bundle.
            // Finder is macOS itself: quit, it is back at once.
            let apple = running.filter { app in
                !app.isMenuBar && app.bundlePath?.hasSuffix("/Finder.app") != true
                    && app.bundlePath.map { scanner.signature(at: $0)?.isApple == true } == true
            }
            let trees = scanner.responsibleTrees(for: Set(apple.map(\.pid)))
            var input = GroupBuilder.Input(processes: processes, catalog: catalog, runningApps: running, installed: apps, excludedTeams: excluded, ownPID: ownPID)
            input.ports = ProcessScanner.listeningPorts()
            input.appleApps = apple.compactMap { app in
                app.bundlePath.map { GroupBuilder.AppleApp(pid: app.pid, name: app.name, path: $0, processes: trees[app.pid] ?? []) }
            }
            return (apps, GroupBuilder.build(input, scanner: scanner))
            }
            guard let self else { return }
            if rereadsApps {
                self.installed = apps
                self.installedReadAt = Date()
            }
            self.apply(result, scan: scan)
        }
    }

    private func apply(_ result: ScanResult, scan: Int) {
        // Demo data came on, or the droplet went away, while it ran.
        guard !isDemo, host != nil else {
            isScanning = false
            rescanRequested = false
            return
        }
        // It saw what has been closed since as still running: the guard would
        // take a closed vendor's stale entry for its app being opened again.
        guard scan >= acceptedScan else {
            isScanning = false
            rescanRequested = false
            refresh()
            return
        }
        withAnimation(Date().timeIntervalSince(endedAt) < 6 ? DroppyAnimation.state : nil) {
            groups = result.groups
            hidden = result.hidden
            tasks = result.tasks
        }
        hasScanned = true
        isScanning = false
        if let awaited = refreshAwaits, scan >= awaited {
            refreshAwaits = nil
            finishRefresh()
        }
        guardClosed()
        publishLayoutChange()
        if rescanRequested {
            rescanRequested = false
            refresh()
        }
    }

    /// The refresh button. It spins for at least a moment, so an instant scan
    /// still reads as one, and shows success only once a scan started after
    /// the press has really finished; one that never comes back gives up.
    func refreshByHand() {
        guard refreshPhase == .idle else { return }
        refreshPhase = .working
        refreshStartedAt = Date()
        if isDemo {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                self.finishRefresh()
            }
            return
        }
        // The scan running now saw the list before the press: wait for the next.
        refreshAwaits = scansStarted + 1
        refresh()
        let awaited = refreshAwaits
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard self.refreshPhase == .working, self.refreshAwaits == awaited else { return }
            self.refreshAwaits = nil
            self.refreshPhase = .idle
        }
    }

    private var refreshStartedAt = Date.distantPast

    private func finishRefresh() {
        let shortest = 0.7
        let waited = Date().timeIntervalSince(refreshStartedAt)
        Task { @MainActor in
            if waited < shortest { try? await Task.sleep(for: .seconds(shortest - waited)) }
            guard self.refreshPhase == .working else { return }
            self.host?.feedback.play(.success)
            self.refreshPhase = .done
            try? await Task.sleep(for: .seconds(1.2))
            self.refreshPhase = .idle
        }
    }

    /// The groups the list shows: those with something in the background,
    /// or every one when the person asked for that. Closed vendors have
    /// their own section.
    var visibleGroups: [AppGroup] {
        let closedIDs = Set(state.closed.map(\.id))
        // Open apps first, then what was left behind; heaviest first in each.
        return groups
            .filter { group in
                !closedIDs.contains(group.id) && (showsAll || group.hasBackground || group.isAppRunning) && !group.closableProcesses.isEmpty
            }
            .sorted { ($0.isAppRunning ? 0 : 1, $1.memory, $0.name) < ($1.isAppRunning ? 0 : 1, $0.memory, $1.name) }
    }

    func group(_ id: String) -> AppGroup? { groups.first { $0.id == id } }

    // MARK: Closing

    func tasks(in category: Category) -> [TaskGroup] { tasks.filter { $0.category == category } }

    func task(_ id: String) -> TaskGroup? { tasks.first { $0.id == id } }

    /// Closed servers: their launchd job is out until Restore.
    var stoppedServers: [ClosedGroup] { state.closed.filter { $0.id.hasPrefix("server|") } }

    /// Closed apps and vendor services.
    var closedApps: [ClosedGroup] { state.closed.filter { !$0.id.hasPrefix("server|") } }

    private func discardRunningScans() {
        acceptedScan = scansStarted + 1
    }

    public func requestClose(_ id: String) {
        requestClose(.group(id))
    }

    /// The first press of a close button: the row asks to be confirmed.
    func requestClose(_ target: ConfirmTarget) {
        guard working[workingID(of: target)] == nil else { return }
        host?.feedback.play(.tick)
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { confirming = target }
    }

    public func cancelConfirmation() {
        guard confirming != nil else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { confirming = nil }
    }

    // MARK: Tools

    /// The corner disc flowing into its panel and back; the widget grows with
    /// it when the list is too short to hold the panel.
    func setToolsOpen(_ open: Bool, animated: Bool = true) {
        guard isToolsOpen != open else { return }
        if open {
            confirming = nil
            host?.feedback.play(.tick)
            power.refresh()
        }
        // Droppy's own spring with a small bounce on the way out; none on the way back.
        withAnimation(animated ? (open ? DroppyAnimation.stateEmphasis : DroppyAnimation.controlMorph) : nil) {
            isToolsOpen = open
            publishLayoutChange()
        }
    }

    func setKeepsAwake(_ on: Bool) {
        let done = power.setKeepsAwake(on)
        host?.feedback.play(done ? .tick : .failure)
    }

    func setLidClosed(_ on: Bool) {
        host?.feedback.play(.tick)
        power.setLidClosed(on) { [weak self] done in
            guard let self else { return }
            // A refused password is no event: the switch going back says it.
            self.host?.feedback.play(done ? .success : .failure)
            guard done else { return }
            self.record(.note, on ? "Lid closed mode turned on." : "Lid closed mode turned off.")
            self.save()
        }
    }

    var skipsPasswordBinding: Binding<Bool> {
        Binding(
            get: { self.power.ruleWanted ?? self.power.skipsPassword },
            set: { on in
                self.host?.feedback.play(.tick)
                self.power.setSkipsPassword(on) { [weak self] done in
                    guard let self else { return }
                    self.host?.feedback.play(done ? .success : .failure)
                    guard done else { return }
                    self.record(.note, on ? "Lid closed mode now switches without a password." : "Lid closed mode asks for a password again.")
                    self.save()
                }
            }
        )
    }

    /// What the panel's red button closes on the list on screen. Apps: only
    /// what is left of apps that are not open, so no open work is touched.
    /// Servers: launchd services only when the panel's switch says so.
    private var closeAllGroups: [AppGroup] {
        guard selectedTab == .apps else { return [] }
        return visibleGroups.filter { group in
            // A menu bar app is open as far as the person is concerned.
            let isInMenuBar = group.processes.contains { $0.kind == .app && $0.isMenuBar }
            // A vendor's shared services serve its open apps; the guard would
            // only bring them back.
            let servesOpenApp = group.id.hasSuffix("|shared") && visibleGroups.contains { $0.teamID == group.teamID && $0.isAppRunning }
            return !group.isHost && !group.isAppRunning && !isInMenuBar && !servesOpenApp && working[group.id] == nil
        }
    }

    private var closeAllTasks: [TaskGroup] {
        guard selectedTab != .apps else { return [] }
        return tasks(in: selectedTab).filter { task in
            working[task.id] == nil && (selectedTab != .servers || includesServices || task.job == nil)
        }
    }

    var canCloseAll: Bool { !closeAllGroups.isEmpty || !closeAllTasks.isEmpty }

    /// Each row closes its usual way.
    func closeAll() {
        // A hold can outlive its panel: a scroll closes it under the pointer.
        guard isToolsOpen, canCloseAll else { return }
        let groups = closeAllGroups
        let tasks = closeAllTasks
        host?.feedback.play(.tick)
        endedAt = Date()
        setToolsOpen(false)
        for group in groups { close(group.id) }
        for task in tasks { closeTask(task.id) }
    }

    /// The key under which `working` follows a target while it closes.
    private func workingID(of target: ConfirmTarget) -> String {
        switch target {
        case .group(let id), .task(let id): return id
        case .item(_, let item): return item
        case let .cluster(group, cluster): return "\(group)#\(cluster)"
        }
    }

    /// What confirming would end, for the row's subtitle while it asks.
    func killNote(for target: ConfirmTarget) -> String {
        let count: Int
        switch target {
        case .group(let id):
            guard let group = group(id) else { return "" }
            count = group.closableProcesses.count
            if count == 0, !group.jobs.isEmpty {
                return Phrases.jobsWillBeTurnedOff(group.jobs.count)
            }
        case .task(let id):
            count = task(id)?.processes.count ?? 0
        case let .item(taskID, itemID):
            count = task(taskID)?.items.first { $0.id == itemID }?.processes.count ?? 0
        case let .cluster(groupID, clusterID):
            count = group(groupID).flatMap { group in
                ProcessCluster.clusters(of: group.processes).first { $0.id == clusterID }
            }?.entries.filter { !$0.isPrivileged }.count ?? 0
        }
        return Phrases.processesWillBeKilled(count)
    }

    public func confirmClose() {
        guard let target = confirming else { return }
        host?.feedback.play(.tick)
        endedAt = Date()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { confirming = nil }
        switch target {
        case .group(let id): close(id)
        case .task(let id): closeTask(id)
        case let .item(taskID, itemID): closeItem(taskID, itemID)
        case let .cluster(groupID, clusterID): closeCluster(groupID, clusterID)
        }
    }

    /// A tool's sessions or a server's tree. A server run by launchd is taken
    /// out of it first, so it stays stopped, and kept for Restore.
    func closeTask(_ id: String) {
        guard let task = task(id), working[id] == nil else { return }
        working[id] = "Closing"
        let persists = persistsAcrossRestart
        let targets = task.processes
        let job = task.job
        Task { @MainActor in
            let killed: Int
            var stopped = job.map { StoppedJob(job: $0, wasLoaded: true) }
            if self.isDemo {
                try? await Task.sleep(for: .seconds(1))
                killed = targets.count
            } else {
                let outcome = await BlockingWork.run { () -> (killed: Int, stopped: StoppedJob?, failed: Bool) in
                    guard let job else { return (Closer.end(targets), nil, false) }
                    let since = Date().addingTimeInterval(-Closer.respawnWindow)
                    let resolved = Launchctl.resolved(job)
                    let wasDisabled = Launchctl.disabledLabels(in: .user).contains(job.label)
                    // Still loaded, launchd would only start it again.
                    guard Launchctl.stop(resolved, persist: persists) else { return (0, nil, true) }
                    let killed = Closer.end(targets, respawning: Set(targets.values), since: since)
                    return (killed, StoppedJob(job: resolved, wasLoaded: true, wasDisabled: wasDisabled), false)
                }
                if outcome.failed {
                    self.working[id] = nil
                    self.record(.refused, "launchd did not let go of \(task.name), so nothing was ended.")
                    self.save()
                    self.host?.feedback.play(.failure)
                    self.presentStrip(symbol: "exclamationmark.triangle.fill", tint: .orange, title: task.name, detail: "Could not stop")
                    return
                }
                killed = outcome.killed
                stopped = outcome.stopped
            }
            self.discardRunningScans()
            withAnimation(DroppyAnimation.state) {
                self.working[id] = nil
                if self.isDemo {
                    if job != nil { self.demoStash[id] = task }
                    self.tasks.removeAll { $0.id == id }
                }
            }
            if let stopped {
                self.state.closed.removeAll { $0.id == id }
                self.state.closed.append(ClosedGroup(
                    id: id,
                    name: task.name,
                    iconPath: nil,
                    jobs: [stopped],
                    persisted: persists,
                    closedAt: Date(),
                    processCount: killed,
                    freedMemory: task.memory,
                    paths: Array(Set(targets.values))
                ))
            }
            self.record(.closed, job != nil
                ? "\(task.name): \(Phrases.processesEnded(killed)). Its launchd job was stopped."
                : "\(task.name): \(Phrases.processesEnded(killed)).")
            self.save()
            self.host?.feedback.play(.success)
            self.presentStrip(symbol: "xmark.circle.fill", tint: Self.closeTint, title: task.name, detail: "−\(killed) · \(Bytes.text(task.memory))")
            self.refresh()
            self.publishLayoutChange()
        }
    }

    func closeItem(_ taskID: String, _ itemID: String) {
        guard let task = task(taskID), let item = task.items.first(where: { $0.id == itemID }) else { return }
        end(item.processes, name: "\(task.name): \(item.title)", memory: item.memory, busyID: itemID)
    }

    func closeCluster(_ groupID: String, _ clusterID: String) {
        guard let group = group(groupID),
              let cluster = ProcessCluster.clusters(of: group.processes).first(where: { $0.id == clusterID }) else { return }
        let entries = cluster.entries.filter { !$0.isPrivileged }
        let targets = Dictionary(uniqueKeysWithValues: entries.map { ($0.pid, $0.path) })
        let busyID = "\(groupID)#\(clusterID)"
        let apps = entries.filter { $0.kind == .app }.map(\.pid)
        let labels = Set(entries.compactMap(\.label).filter { !$0.hasPrefix("application.") })
        let jobs = group.jobs.filter { $0.domain == .user && labels.contains($0.label) }
        guard !isDemo, working[busyID] == nil, !(apps.isEmpty && jobs.isEmpty) else {
            end(targets, name: cluster.first.name, memory: cluster.memory, busyID: busyID)
            return
        }
        working[busyID] = "Closing"
        Task { @MainActor in
            // What the row's note promises. An app quits the normal way, and
            // with unsaved work it stays. A job leaves launchd first, until the
            // next login: without a record, Restore could not bring it back.
            if let stuck = await self.quit(apps) {
                self.refuse(busyID, name: stuck, "\(stuck) did not quit, maybe it has unsaved work. Nothing else was closed.", detail: "Still open")
                return
            }
            let failed = await BlockingWork.run {
                jobs.filter { !Launchctl.stop($0, persist: false) }.map(\.label)
            }
            if !failed.isEmpty {
                self.refuse(busyID, name: cluster.first.name, "launchd did not let go of \(cluster.first.name), so it was left running.", detail: "Could not stop")
                return
            }
            self.working[busyID] = nil
            let remaining = targets.filter { !apps.contains($0.key) }
            self.end(remaining, name: cluster.first.name, memory: cluster.memory, busyID: busyID)
        }
    }

    /// Asks apps to quit and waits. The name of one that stayed, if any.
    private func quit(_ pids: [pid_t]) async -> String? {
        let apps = pids.compactMap { NSRunningApplication(processIdentifier: $0) }
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(10)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
        return apps.first { !$0.isTerminated }.map { $0.localizedName ?? "The app" }
    }

    private func refuse(_ busyID: String, name: String, _ sentence: String, detail: String) {
        working[busyID] = nil
        record(.refused, sentence)
        save()
        presentStrip(symbol: "exclamationmark.triangle.fill", tint: .orange, title: name, detail: detail)
        host?.feedback.play(.failure)
    }

    /// Ends processes and their children, nothing more.
    private func end(_ targets: [pid_t: String], name: String, memory: UInt64, busyID: String) {
        guard working[busyID] == nil else { return }
        working[busyID] = "Closing"
        Task { @MainActor in
            let killed: Int
            if self.isDemo {
                try? await Task.sleep(for: .seconds(1))
                killed = targets.count
            } else {
                killed = await BlockingWork.run { Closer.end(targets) }
            }
            self.discardRunningScans()
            withAnimation(DroppyAnimation.state) {
                self.working[busyID] = nil
                if self.isDemo { self.removeFromDemo(Set(targets.keys)) }
            }
            self.record(.closed, "\(name): \(Phrases.processesEnded(killed)).")
            self.save()
            self.host?.feedback.play(.success)
            self.presentStrip(symbol: "xmark.circle.fill", tint: Self.closeTint, title: name, detail: "−\(killed) · \(Bytes.text(memory))")
            self.refresh()
        }
    }

    /// Closes the apps, takes the vendor's jobs out of launchd so nothing
    /// starts them again, then ends whatever is left: SIGTERM, a moment,
    /// SIGKILL.
    func close(_ id: String) {
        guard let group = group(id), !group.isHost, working[id] == nil else { return }
        working[id] = "Closing"
        expanded.remove(id)
        // Read now: a droplet switched off mid-close can no longer read them,
        // and the defaults would disable jobs against the person's setting.
        let persists = persistsAcrossRestart
        let includesSystem = includesSystem
        if isDemo {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                self.finishClose(group, stoppedJobs: [], failedJobs: [], killed: group.closableProcesses.count, adminRefused: false, persists: persists, includesSystem: includesSystem)
            }
            return
        }

        Task { @MainActor in
            // 1. The apps, the polite way: an app with unsaved work asks first.
            if let stuck = await self.quit(group.processes.filter { $0.kind == .app }.map(\.pid)) {
                self.refuse(id, name: stuck, "\(stuck) did not quit, maybe it has unsaved work. Nothing else was closed.", detail: "Still open")
                return
            }

            // 2. The jobs and every process left, off the main thread.
            let scanner = self.scanner
            let outcome = await BlockingWork.run {
                Closer.stop(group, persist: persists, includeSystem: includesSystem, scanner: scanner)
            }
            self.finishClose(group, stoppedJobs: outcome.jobs, failedJobs: outcome.failedJobs, killed: outcome.killed, adminRefused: outcome.adminRefused, persists: persists, includesSystem: includesSystem)
        }
    }

    private func finishClose(_ group: AppGroup, stoppedJobs: [StoppedJob], failedJobs: [String], killed: Int, adminRefused: Bool, persists: Bool, includesSystem: Bool) {
        discardRunningScans()
        let freed = group.processes.filter { $0.kind != .system }.reduce(0) { $0 + $1.memory }
        withAnimation(DroppyAnimation.state) {
            working[group.id] = nil
            state.closed.removeAll { $0.id == group.id }
            // An app with nothing in the background and no jobs only quit:
            // there is nothing to keep closed.
            if !stoppedJobs.isEmpty || group.hasBackground {
                state.closed.append(ClosedGroup(
                    id: group.id,
                    name: group.name,
                    iconPath: group.iconPath,
                    jobs: stoppedJobs,
                    persisted: persists,
                    closedAt: Date(),
                    processCount: killed,
                    freedMemory: freed,
                    paths: Array(Set(group.processes.map(\.path)))
                ))
            }
            if isDemo, stoppedJobs.isEmpty, !group.hasBackground {
                // Only quit: on a real Mac the next scan drops it.
                groups.removeAll { $0.id == group.id }
            }
        }
        var line = group.isIdle || group.closableProcesses.isEmpty
            ? "\(group.name): \(Phrases.jobsTurnedOff(stoppedJobs.count))."
            : "\(group.name): \(Phrases.processesEnded(killed)), \(Phrases.jobsStopped(stoppedJobs.count))."
        if group.privilegedCount > 0, !includesSystem {
            line += " " + Phrases.servicesLeftRunning(group.privilegedCount)
        } else if adminRefused {
            line += " The password was not given, so system services were left running."
        }
        if !failedJobs.isEmpty {
            line += " launchd did not let go of \(failedJobs.joined(separator: ", ")), so it can come back."
        }
        record(.closed, line)
        save()
        host?.feedback.play(.success)
        if failedJobs.isEmpty {
            presentStrip(symbol: "xmark.circle.fill", tint: Self.closeTint, title: group.name, detail: "−\(killed) · \(Bytes.text(freed))")
        } else {
            presentStrip(symbol: "exclamationmark.triangle.fill", tint: .orange, title: group.name, detail: "Could not stop \(failedJobs.count)")
        }
        refresh()
        publishLayoutChange()
    }

    // MARK: Guarding

    /// After every scan: a closed vendor whose app was opened comes back, and
    /// anything else of it that started again is closed again.
    private func guardClosed() {
        guard !state.closed.isEmpty else { return }
        let now = Date()

        // Follow up on the polite request from the last pass.
        for (pid, entry) in terminating where now.timeIntervalSince(entry.at) > 2 {
            if ProcessScanner.isAlive(pid), ProcessScanner.path(of: pid) == entry.path {
                kill(pid, SIGKILL)
            }
            terminating[pid] = nil
        }

        for closed in state.closed where working[closed.id] == nil {
            // A stopped server running again was started again by someone:
            // saying "Stopped" over it would be false, and nothing is left to
            // give back.
            if closed.id.hasPrefix("server|") {
                if task(closed.id) != nil {
                    state.closed.removeAll { $0.id == closed.id }
                    record(.note, "\(closed.name) was started again.")
                    publishLayoutChange()
                }
                continue
            }
            // A window app is the person opening it again: its own app for an
            // app's group, any app of the vendor for its shared services. A
            // menu bar app is what helpers start, so it is closed with them.
            let team = AppGroup.teamID(of: closed.id)
            let reopened = groups
                .filter { closed.id.hasSuffix("|shared") ? $0.teamID == team : $0.id == closed.id }
                .lazy
                .flatMap(\.processes)
                .first { $0.kind == .app && !$0.isMenuBar }
            if let reopened {
                if autoRestore, !restoreRefused.contains(closed.id) { restore(closed.id, openedApp: reopened.name) }
                continue
            }
            guard guardsClosed, let group = group(closed.id) else { continue }
            // Several copies of one helper in a pass are one coming back.
            var countedThisPass = Set<String>()
            for process in group.processes where (process.kind.isBackground || process.isMenuBar) && !process.isPrivileged {
                guard terminating[process.pid] == nil, !givenUp.contains(process.path) else { continue }
                // The scan is a moment old: the pid may be someone else's now.
                guard ProcessScanner.path(of: process.pid) == process.path else { continue }
                var times = (reclosedAt[process.path] ?? []).filter { now.timeIntervalSince($0) < 60 }
                if countedThisPass.insert(process.path).inserted { times.append(now) }
                reclosedAt[process.path] = times
                if times.count > 6 {
                    givenUp.insert(process.path)
                    record(.refused, "\(process.name) keeps coming back, something outside launchd starts it. K*llTree stopped closing it.")
                    continue
                }
                kill(process.pid, SIGTERM)
                terminating[process.pid] = (process.path, now)
                if let index = state.closed.firstIndex(where: { $0.id == closed.id }) {
                    state.closed[index].reclosed += 1
                }
                record(.reclosed, "\(process.name) started again and was closed again.")
            }
        }
        if stateChanged { save() }
    }

    // MARK: Restoring

    /// Gives the vendor's jobs back. The record goes only once that worked: a
    /// refused password leaves the row, with the Restore button to try again.
    public func restore(_ id: String, openedApp: String? = nil) {
        guard let closed = state.closed.first(where: { $0.id == id }), working[id] == nil else { return }
        if isDemo {
            if let task = demoStash.removeValue(forKey: id) { tasks.append(task) }
            finishRestore(closed, openedApp: openedApp)
            return
        }
        working[id] = "Restoring"
        let jobs = closed.jobs
        Task { @MainActor in
            let isBack = await BlockingWork.run { Closer.start(jobs) }
            self.working[id] = nil
            if isBack {
                self.restoreRefused.remove(id)
                self.finishRestore(closed, openedApp: openedApp)
            } else {
                self.restoreRefused.insert(id)
                self.refuse(id, name: closed.name, "\(closed.name) stays closed because the password was not given.", detail: "Not restored")
            }
        }
    }

    private func finishRestore(_ closed: ClosedGroup, openedApp: String?) {
        state.closed.removeAll { $0.id == closed.id }
        let paths = Set((closed.paths ?? []) + (group(closed.id)?.processes.map(\.path) ?? []))
        givenUp.subtract(paths)
        paths.forEach { reclosedAt[$0] = nil }
        record(.restored, openedApp.map { "\(closed.name) is back because \($0) opened." } ?? "\(closed.name) is back.")
        save()
        discardRunningScans()
        presentStrip(symbol: "arrow.uturn.backward.circle.fill", tint: AdaptiveColors.notchSurfaceSecondaryText, title: closed.name, detail: "Back")
        publishLayoutChange()
        refresh()
    }

    /// Takes ended processes out of the made-up Mac, as a rescan would.
    private func removeFromDemo(_ pids: Set<pid_t>) {
        for index in groups.indices {
            groups[index].processes.removeAll { pids.contains($0.pid) }
        }
        for index in tasks.indices {
            tasks[index].items.removeAll { item in Set(item.processes.keys).isSubset(of: pids) }
        }
        tasks.removeAll { $0.items.isEmpty }
        publishLayoutChange()
    }

    public func restoreAll() {
        for closed in state.closed { restore(closed.id) }
    }

    public func clearJournal() {
        state.journal = []
        save()
    }

    private func record(_ kind: JournalEntry.Kind, _ text: String) {
        stateChanged = true
        state.journal.insert(JournalEntry(date: Date(), kind: kind, text: text), at: 0)
        if state.journal.count > KillTreeState.journalLimit {
            state.journal.removeLast(state.journal.count - KillTreeState.journalLimit)
        }
        host?.log.info(text)
    }

    // MARK: HUD

    static let closeTint = Color(red: 1, green: 0.36, blue: 0.33)
    /// A row whose app is closed while its helpers run on sits back.
    static let closedAppOpacity: Double = 0.5

    /// `always`: a safety notice, shown even with result strips turned off.
    private func presentStrip(symbol: String, tint: Color, title: String, detail: String, always: Bool = false) {
        guard let host, showsHUD || always else { return }
        let request = DropletHUDRequest(
            id: "killtree.result",
            duration: 2.2,
            priority: .normal,
            accessibilityLabel: "\(title), \(detail)"
        ) {
            ResultStrip(symbol: symbol, tint: tint, title: title, detail: detail)
        }
        _ = host.hud.present(request)
    }

    // MARK: Screens

    public func finishWelcome() {
        host?.preferences.setValue(true, forKey: Keys.hasSeenWelcome)
        show(.category(.apps))
    }

    func show(_ target: KillTreeScreen) {
        guard screen != target else { return }
        confirming = nil
        isToolsOpen = false
        if case .category(let category) = target { lastCategory = category }
        screen = target
        publishLayoutChange()
    }

    /// The tab spring, Craft's: its segmented controls move their selection
    /// with `UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.97)`,
    /// interruptible, so a second tap mid-flight turns from where it is.
    static var tabSpring: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.3, dampingFraction: 0.97)
    }

    func selectTab(_ category: Category) {
        guard screen != .category(category) else { return }
        host?.feedback.play(.tick)
        withAnimation(Self.tabSpring) { show(.category(category)) }
    }

    var selectedTab: Category {
        if case .category(let category) = screen { return category }
        return lastCategory
    }

    func toggleExpanded(_ id: String) {
        guard group(id)?.isExpandable ?? task(id)?.isExpandable ?? false else { return }
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        publishLayoutChange()
    }

    /// The tick a tip makes as it comes up.
    func tipAppeared() {
        host?.feedback.play(.tick)
    }

    /// The host takes one height for a widget, alone or in a row, and the list's
    /// would stretch a whole row of widgets. So the height follows where the
    /// view is mounted, and the last place is remembered for the next opening.
    func setPaired(_ paired: Bool) {
        guard isPaired != paired else { return }
        isPaired = paired
        host?.preferences.setValue(paired, forKey: Keys.isPaired)
        publishLayoutChange()
    }

    /// From the widget beside others: K*llTree alone on the shelf.
    func openAlone() {
        setPaired(false)
        guard host?.shelf.open(revealing: Self.widgetID) == true else {
            host?.feedback.play(.failure)
            return
        }
        host?.feedback.play(.tick)
    }

    public func openSettings() {
        _ = host?.workspace.openSettings()
    }

    func publishLayoutChange() {
        let height = widgetHeight
        guard height != lastHeight else { return }
        lastHeight = height
        layoutSubject.send(Self.widgetID)
        host?.shelf.invalidateLayout(for: Self.widgetID)
    }

    // MARK: Preferences

    private func preference(_ key: String, default value: Bool) -> Bool {
        host?.preferences.value(forKey: key, default: value) ?? value
    }

    private func binding(_ key: String, default value: Bool, then: (() -> Void)? = nil) -> Binding<Bool> {
        Binding(
            get: { self.preference(key, default: value) },
            set: {
                self.host?.preferences.setValue($0, forKey: key)
                self.objectWillChange.send()
                then?()
            }
        )
    }

    var hasSeenWelcome: Bool { preference(Keys.hasSeenWelcome, default: false) }
    var persistsAcrossRestart: Bool { preference(Keys.persists, default: false) }
    var autoRestore: Bool { preference(Keys.autoRestore, default: true) }
    var guardsClosed: Bool { preference(Keys.guards, default: false) }
    var includesSystem: Bool { preference(Keys.includesSystem, default: false) }
    var showsAll: Bool { preference(Keys.showsAll, default: false) }
    var showsHUD: Bool { preference(Keys.showsHUD, default: true) }
    var includesServices: Bool { preference(Keys.includesServices, default: false) }

    var persistsBinding: Binding<Bool> { binding(Keys.persists, default: false) }
    var autoRestoreBinding: Binding<Bool> { binding(Keys.autoRestore, default: true) { self.updateTimer() } }
    var guardsBinding: Binding<Bool> { binding(Keys.guards, default: false) { self.updateTimer() } }
    var includesSystemBinding: Binding<Bool> { binding(Keys.includesSystem, default: false) }
    var showsAllBinding: Binding<Bool> { binding(Keys.showsAll, default: false) { self.publishLayoutChange() } }
    var showsHUDBinding: Binding<Bool> { binding(Keys.showsHUD, default: true) }
    var includesServicesBinding: Binding<Bool> { binding(Keys.includesServices, default: false) }
    var demoBinding: Binding<Bool> {
        Binding(get: { self.isDemo }, set: { self.setDemo($0) })
    }
}

// MARK: - Shelf widget

extension KillTreeDroplet: ShelfWidgetProviding {
    static let hostInsets: CGFloat = DroppySpacing.sm * 2
    static let navHeight: CGFloat = CategoryNavBar.height
    static let welcomeHeight: CGFloat = 195
    static let pairedWordmarkWidth: CGFloat = 140
    static let pairedButtonHeight: CGFloat = 28
    /// The letters, two lines of text and the button, with their gaps.
    static var pairedHeight: CGFloat {
        hostInsets + KillWordmark.height(forWidth: pairedWordmarkWidth) + 28 + pairedButtonHeight + DroppySpacing.sm * 2
    }
    nonisolated static let groupRowHeight: CGFloat = 40
    nonisolated static let processRowHeight: CGFloat = 24
    nonisolated static let sectionHeaderHeight: CGFloat = 26
    static let rowSpacing: CGFloat = DroppySpacing.sm
    static let listMinHeight: CGFloat = 96
    static let listMaxHeight: CGFloat = 312


    /// Every row a list draws, in order. The view and the height both come
    /// from this, so the widget is always exactly as tall as its rows.
    func rows(for category: Category) -> [ListRow] {
        var rows: [ListRow] = []
        // What is kept closed comes first, while there is any.
        switch category {
        case .apps:
            let closed = closedApps
            let groups = visibleGroups
            if !closed.isEmpty {
                rows.append(.section(.closed, count: closed.count, memory: 0))
                rows += closed.map(ListRow.closed)
                // The rest gets a heading of its own once something sits above it.
                if !groups.isEmpty { rows.append(.section(.running, count: groups.count, memory: 0)) }
            }
            for group in groups {
                let children = group.isExpandable && expanded.contains(group.id) ? ProcessCluster.clusters(of: group.processes) : nil
                rows.append(.group(group, children: children))
            }
        case .terminal, .servers:
            let running = tasks(in: category)
            if category == .servers, !stoppedServers.isEmpty {
                rows.append(.section(.stopped, count: stoppedServers.count, memory: 0))
                rows += stoppedServers.map(ListRow.closed)
                if !running.isEmpty { rows.append(.section(.running, count: running.count, memory: 0)) }
            }
            for task in running {
                rows.append(.task(task, isOpen: task.isExpandable && expanded.contains(task.id)))
            }
        }
        return rows
    }

    /// A row, and when it is open its children under it and the block's
    /// bottom inset.
    nonisolated static func blockHeight(children: Int?) -> CGFloat {
        guard let children else { return groupRowHeight }
        return groupRowHeight + blockChildrenGap + CGFloat(children) * processRowHeight
            + CGFloat(max(children - 1, 0)) * childRowSpacing + blockBottomInset
    }

    /// Between an open block's child rows.
    nonisolated static let childRowSpacing: CGFloat = DroppySpacing.xs

    /// Air inside an open block: between the header and its children, and
    /// under the last child.
    nonisolated static let blockChildrenGap: CGFloat = DroppySpacing.xs
    nonisolated static let blockBottomInset: CGFloat = DroppySpacing.md

    func listHeight(for category: Category) -> CGFloat {
        let rows = rows(for: category)
        let content = rows.isEmpty
            ? Self.listMinHeight
            : rows.map(\.height).reduce(0, +) + CGFloat(rows.count - 1) * Self.rowSpacing + ToolsMetrics.listFooter
        let height = min(max(content, Self.listMinHeight), Self.listMaxHeight)
        // The panel fits inside the widget: over the nav, down to the corner.
        return isToolsOpen ? max(height, ToolsMetrics.panelHeight + ToolsMetrics.islandMargin - Self.navHeight - DroppySpacing.md) : height
    }

    var widgetHeight: CGFloat {
        if isPaired { return Self.pairedHeight }
        switch screen {
        case .welcome:
            return Self.hostInsets + Self.welcomeHeight
        case .category(let category):
            return Self.hostInsets + Self.navHeight + DroppySpacing.md + listHeight(for: category)
        }
    }

    var layoutTraits: ShelfWidgetLayoutTraits {
        ShelfWidgetLayoutTraits(
            preferredSoloWidth: 440,
            preferredPairedWidth: 220,
            contentHeight: .fixed(widgetHeight)
        )
    }

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "K*llTree",
                systemImage: "xmark.circle.fill",
                layoutTraits: layoutTraits,
                searchKeywords: ["process", "quit", "kill", "background", "helper", "adobe", "launchd", "memory"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(KillTreeWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

extension KillTreeDroplet: ShelfWidgetDynamicLayoutProviding {
    public func currentLayoutTraits(for id: ShelfWidgetID) -> ShelfWidgetLayoutTraits? {
        id == Self.widgetID ? layoutTraits : nil
    }

    public var shelfWidgetLayoutInvalidationPublisher: AnyPublisher<ShelfWidgetID, Never> {
        layoutSubject.eraseToAnyPublisher()
    }
}

// MARK: - HUD

extension KillTreeDroplet: HUDPresenting {}

/// The result at the two outer edges, nothing under the camera housing.
private struct ResultStrip: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: DroppySpacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(tint)
                Text(verbatim: title)
                    .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(verbatim: detail)
                .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Settings pane

extension KillTreeDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(KillTreeSettings(droplet: self, power: power))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Keep closed after a restart", keywords: ["login", "launchd", "disable"]),
            SettingsSearchEntry(title: "Bring them back when the app opens", keywords: ["restore", "relaunch"]),
            SettingsSearchEntry(title: "Close again if they come back", keywords: ["guard", "respawn", "keepalive"]),
            SettingsSearchEntry(title: "Also stop system services", keywords: ["root", "daemon", "administrator", "password"]),
            SettingsSearchEntry(title: "Restore everything", keywords: ["restore", "undo"]),
            SettingsSearchEntry(title: "Switch lid closed mode without a password", keywords: ["sleep", "lid", "password", "sudo"])
        ]
    }
}
