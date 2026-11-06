import AppKit
import DroppyKit
import DroppyKitHarness
import XCTest
@testable import KillTree

// MARK: - A throwaway executable

/// Compiled once per run to a unique path, so nothing but these tests' own
/// processes can match it. Each copy ends itself after a minute regardless.
private enum Dummy {
    static let path: String = {
        let source = """
        #include <signal.h>
        #include <string.h>
        #include <unistd.h>
        int main(int c, char **v) {
            alarm(60);
            const char *m = c > 1 ? v[1] : "sleep";
            if (!strcmp(m, "stubborn")) signal(SIGTERM, SIG_IGN);
            if (!strcmp(m, "parent") || !strcmp(m, "orphan")) {
                pid_t p = fork();
                if (p == 0) { alarm(60); setsid(); for (;;) pause(); }
                if (!strcmp(m, "orphan")) _exit(0);
            }
            for (;;) pause();
        }
        """
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("killtree-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("dummy.c")
        try! source.write(to: file, atomically: true, encoding: .utf8)
        let binary = folder.appendingPathComponent("killtree-test-dummy").path
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/cc")
        compile.arguments = ["-o", binary, file.path]
        try! compile.run()
        compile.waitUntilExit()
        precondition(compile.terminationStatus == 0)
        return String(cString: realpath(binary, nil))
    }()

    static func spawn(_ mode: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = [mode]
        try process.run()
        usleep(150_000)
        return process
    }

    static var pids: [pid_t] {
        ProcessScanner().scan(signatures: false).filter { $0.path == path }.map(\.pid)
    }

    static func cleanUp() {
        for pid in pids { kill(pid, SIGKILL) }
    }
}

// MARK: - Closing

final class CloserTests: XCTestCase {
    override func tearDown() { Dummy.cleanUp() }

    func testChildGoesWithItsParentAndABystanderStays() throws {
        let target = try Dummy.spawn("parent")
        let bystander = try Dummy.spawn("sleep")
        let child = Set(Dummy.pids).subtracting([target.processIdentifier, bystander.processIdentifier]).first!
        Closer.end([target.processIdentifier: Dummy.path])
        usleep(200_000)
        XCTAssertNil(ProcessScanner.path(of: child))
        XCTAssertFalse(target.isRunning)
        XCTAssertTrue(bystander.isRunning)
    }

    func testStubbornProcessGetsSIGKILL() throws {
        let process = try Dummy.spawn("stubborn")
        Closer.end([process.identifierForTest: Dummy.path])
        usleep(200_000)
        XCTAssertFalse(process.isRunning)
    }

    func testPIDRunningSomethingElseIsNotHit() throws {
        let process = try Dummy.spawn("sleep")
        Closer.end([process.identifierForTest: "/nonexistent/other-binary"])
        XCTAssertTrue(process.isRunning)
    }

    /// The bug this guards: closing one `node` ended every orphaned `node`.
    func testUnrelatedOrphanOfSameExecutableStays() throws {
        let maker = try Dummy.spawn("orphan")
        maker.waitUntilExit()
        usleep(200_000)
        let orphan = try XCTUnwrap(Dummy.pids.first)
        let target = try Dummy.spawn("sleep")
        Closer.end([target.identifierForTest: Dummy.path])
        usleep(200_000)
        XCTAssertFalse(target.isRunning)
        XCTAssertEqual(ProcessScanner.path(of: orphan), Dummy.path, "not a job's, so not a respawn")
    }

    func testOldOrphanStaysEvenWhenTheExecutableRespawns() throws {
        let maker = try Dummy.spawn("orphan")
        maker.waitUntilExit()
        usleep(200_000)
        let orphan = try XCTUnwrap(Dummy.pids.first)
        let target = try Dummy.spawn("sleep")
        Closer.end([target.identifierForTest: Dummy.path], respawning: [Dummy.path], since: Date().addingTimeInterval(60))
        usleep(200_000)
        XCTAssertEqual(ProcessScanner.path(of: orphan), Dummy.path, "started before the close")
    }

    func testFreshOrphanOfARespawningJobGoes() throws {
        let since = Date().addingTimeInterval(-5)
        let maker = try Dummy.spawn("orphan")
        maker.waitUntilExit()
        usleep(200_000)
        let target = try Dummy.spawn("sleep")
        Closer.end([target.identifierForTest: Dummy.path], respawning: [Dummy.path], since: since)
        usleep(200_000)
        XCTAssertTrue(Dummy.pids.isEmpty)
    }

    func testRootKillCommandChecksWhatThePIDRuns() throws {
        // Through a shell: Foundation shortens /private/var to /var, and `ps`
        // reports the path as given to exec. launchd's jobs run from their
        // full path. A path that differs only skips the signal: it fails safe.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec '\(Dummy.path)' sleep"]
        try process.run()
        usleep(200_000)
        print("PS:", Launchctl.run(executable: "/bin/ps", ["-o", "comm=", "-p", "\(process.processIdentifier)"]).output ?? "")
        func run(path: String) {
            let shell = Process()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", Closer.rootKillCommand(pid: process.identifierForTest, path: path)]
            try! shell.run()
            shell.waitUntilExit()
        }
        run(path: "/nonexistent/other binary")
        usleep(100_000)
        XCTAssertTrue(process.isRunning, "another executable behind the pid: left alone")
        run(path: Dummy.path)
        usleep(200_000)
        XCTAssertFalse(process.isRunning)
    }
}

private extension Process {
    var identifierForTest: pid_t { processIdentifier }
}

// MARK: - launchd, with a job of the tests' own

final class LaunchdTests: XCTestCase {
    private let label = "dev.8lx.killtree-test"
    private var job: LaunchJob!

    override func setUpWithError() throws {
        let plist: [String: Any] = ["Label": label, "ProgramArguments": [Dummy.path, "sleep"], "RunAtLoad": true]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let url = URL(fileURLWithPath: (Dummy.path as NSString).deletingLastPathComponent).appendingPathComponent("\(label).plist")
        try data.write(to: url)
        job = LaunchJob(label: label, plistPath: url.path, domain: .user, program: Dummy.path, keepAlive: false, runAtLoad: true, associatedBundleIDs: [])
        Launchctl.run(["enable", job.serviceTarget])
        Launchctl.run(["bootout", job.serviceTarget])
        XCTAssertEqual(Launchctl.run(["bootstrap", job.domain.target, url.path]).status, 0)
    }

    override func tearDown() {
        Launchctl.run(["bootout", job.serviceTarget])
        Launchctl.run(["enable", job.serviceTarget])
        Dummy.cleanUp()
    }

    func testStopAndStartGiveTheJobBack() {
        XCTAssertTrue(Launchctl.isLoaded(job))
        XCTAssertTrue(Launchctl.stop(job, persist: true))
        XCTAssertFalse(Launchctl.isLoaded(job))
        XCTAssertTrue(Launchctl.disabledLabels(in: .user).contains(label))
        XCTAssertTrue(Closer.start([StoppedJob(job: job, wasLoaded: true, wasDisabled: false)]))
        XCTAssertTrue(Launchctl.isLoaded(job))
        XCTAssertFalse(Launchctl.disabledLabels(in: .user).contains(label))
    }

    func testRestoreLeavesWhatThePersonDisabledDisabled() {
        Launchctl.run(["disable", job.serviceTarget])
        XCTAssertTrue(Launchctl.stop(job, persist: true))
        XCTAssertTrue(Closer.start([StoppedJob(job: job, wasLoaded: false, wasDisabled: true)]))
        XCTAssertTrue(Launchctl.disabledLabels(in: .user).contains(label))
        XCTAssertFalse(Launchctl.isLoaded(job))
    }

    func testStoppingAJobThatIsNotLoadedIsNoFailure() {
        XCTAssertTrue(Launchctl.stop(job, persist: false))
        XCTAssertTrue(Launchctl.stop(job, persist: false))
    }

    func testResolvedFindsThePlistOfAJobKnownOnlyByLabel() {
        let bare = LaunchJob(label: label, plistPath: nil, domain: .user, program: nil, keepAlive: false, runAtLoad: false, associatedBundleIDs: [])
        XCTAssertEqual(Launchctl.resolved(bare).plistPath, job.plistPath)
    }

    func testClosingAGroupEndsItsProcessAndRecordsItsJob() throws {
        usleep(300_000)
        let pid = try XCTUnwrap(Dummy.pids.first, "RunAtLoad started it")
        let entry = ProcessEntry(pid: pid, name: "dummy", path: Dummy.path, memory: 0, kind: .agent, label: label, keepAlive: false, isPrivileged: false)
        let group = AppGroup(id: "t|shared", teamID: "t", name: "T", organization: nil, iconPath: nil, appPath: nil, runningApps: [], processes: [entry], jobs: [job], loadedLabels: [label])
        let outcome = Closer.stop(group, persist: false, includeSystem: false, scanner: ProcessScanner())
        XCTAssertEqual(outcome.failedJobs, [])
        XCTAssertEqual(outcome.jobs.first?.wasLoaded, true)
        XCTAssertEqual(outcome.jobs.first?.wasDisabled, false)
        usleep(200_000)
        XCTAssertNil(ProcessScanner.path(of: pid))
        XCTAssertFalse(Launchctl.isLoaded(job))
    }

    func testDisabledParser() {
        let output = """
        disabled services = {
            "a.one" => disabled
            "a.two" => enabled
            "a.three" => true
            "a.four" => false
        }
        login item associations = {
            "x" => ["y"]
        }
        """
        XCTAssertEqual(Launchctl.parseDisabled(output), ["a.one", "a.three"])
    }
}

// MARK: - Tools run with a deadline

final class DeadlineTests: XCTestCase {
    override func tearDown() { Dummy.cleanUp() }

    func testAHungToolIsStoppedAtTheDeadline() {
        let started = Date()
        let result = Launchctl.run(executable: Dummy.path, ["sleep"], timeout: 0.5)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), 4)
        XCTAssertTrue(Dummy.pids.isEmpty)
    }

    func testAToolThatIgnoresSIGTERMStillEnds() {
        let started = Date()
        _ = Launchctl.run(executable: Dummy.path, ["stubborn"], timeout: 0.5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        XCTAssertTrue(Dummy.pids.isEmpty)
    }

    func testAFinishedToolGivesItsOutput() {
        let result = Launchctl.run(executable: "/bin/echo", ["hello"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "hello\n")
    }

    func testCancelRunningStopsAScan() {
        let started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { Launchctl.cancelRunning() }
        _ = Launchctl.run(executable: Dummy.path, ["sleep"], timeout: 20)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
}

// MARK: - Stored state

final class StateTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("killtree-state-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testUnreadableStateIsKeptAside() throws {
        let dir = try folder()
        let url = dir.appendingPathComponent("state.json")
        try Data("{ not json".utf8).write(to: url)
        XCTAssertTrue(KillTreeState.load(from: url).closed.isEmpty)
        KillTreeState().save(to: url)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let aside = try XCTUnwrap(names.first { $0.hasPrefix("state.corrupt-") })
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(aside), encoding: .utf8), "{ not json")
    }

    func testRecordsFromBeforeTheNewFieldsStillLoad() throws {
        let url = try folder().appendingPathComponent("state.json")
        let job = #"{"label":"a.b","plistPath":"/x.plist","domain":"user","program":null,"keepAlive":false,"runAtLoad":false,"associatedBundleIDs":[]}"#
        let old = #"{"closed":[{"id":"t|shared","name":"T","jobs":[{"job":"# + job + #","wasLoaded":true}],"persisted":true,"closedAt":0,"processCount":1,"freedMemory":0,"reclosed":2}],"journal":[]}"#
        try Data(old.utf8).write(to: url)
        let closed = try XCTUnwrap(KillTreeState.load(from: url).closed.first)
        XCTAssertEqual(closed.reclosed, 2)
        XCTAssertNil(closed.jobs[0].wasDisabled)
        XCTAssertNil(closed.paths)
    }
}

// MARK: - Who is listed where

final class ClassificationTests: XCTestCase {
    private func raw(_ pid: pid_t, _ path: String, tty: String? = nil) -> RawProcess {
        RawProcess(pid: pid, ppid: 1, uid: getuid(), path: path, memory: 0, signature: nil, tty: tty, startedAt: nil)
    }

    private func build(_ items: [(RawProcess, HiddenProcess.Reason)], ports: [pid_t: [Int]] = [:], jobs: [pid_t: String] = [:], host: Set<pid_t> = []) -> [TaskGroup] {
        TaskBuilder.build(
            hidden: items.map { HiddenProcess(pid: $0.0.pid, name: "x", path: $0.0.path, memory: 0, reason: $0.1) },
            byPID: Dictionary(uniqueKeysWithValues: items.map { ($0.0.pid, $0.0) }),
            jobByPID: jobs,
            jobsByLabel: [:],
            ports: ports,
            host: host
        )
    }

    func testAnAppsHelperIsNoServer() {
        let helper = raw(4_000_001, "/Applications/Figma.app/Contents/Frameworks/x/chrome_crashpad_handler")
        XCTAssertTrue(build([(helper, .unsigned)]).isEmpty)
        XCTAssertEqual(build([(helper, .unsigned)], ports: [helper.pid: [8080]]).count, 1, "unless it serves a port")
    }

    func testWhatAnotherProgramStartedIsNoServer() {
        XCTAssertTrue(build([(raw(4_000_002, "/opt/x/tool"), .foreignParent("Editor"))]).isEmpty)
    }

    func testALooseScriptIsAServer() {
        XCTAssertEqual(build([(raw(4_000_003, "/opt/x/node"), .runtime)]).first?.category, .servers)
    }

    func testTheHostsChildrenAreOnNoList() {
        let child = raw(4_000_004, "/opt/x/node")
        XCTAssertTrue(build([(child, .runtime)], host: [child.pid]).isEmpty)
    }

    func testALabelWithoutAPlistIsStillAService() {
        let process = raw(4_000_005, "/opt/x/daemon")
        XCTAssertEqual(build([(process, .unsigned)], jobs: [process.pid: "com.x.daemon"]).first?.job?.label, "com.x.daemon")
        XCTAssertNil(build([(process, .unsigned)], jobs: [process.pid: "application.com.x.123"]).first?.job, "launchd's name for an open app")
    }

    func testOtherPeopleAreNotListed() {
        XCTAssertTrue(ProcessScanner.isListable(uid: getuid(), me: getuid()))
        XCTAssertTrue(ProcessScanner.isListable(uid: 0, me: getuid()))
        XCTAssertTrue(ProcessScanner.isServiceAccount(named: "_mxappservice"))
        XCTAssertFalse(ProcessScanner.isServiceAccount(named: "someone"))
        XCTAssertFalse(ProcessScanner.isListable(uid: 100, me: getuid()), "Apple's daemon accounts")
    }
}

// MARK: - Sleep

final class SleepTests: XCTestCase {
    func testParser() {
        XCTAssertTrue(SleepSystem.isSleepDisabled(pmsetOutput: "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 1\n"))
        XCTAssertFalse(SleepSystem.isSleepDisabled(pmsetOutput: " SleepDisabled\t\t0\n"))
        XCTAssertFalse(SleepSystem.isSleepDisabled(pmsetOutput: "Currently in use:\n sleep 1 (sleep prevented by SleepDisabled, powerd)\n"))
        XCTAssertFalse(SleepSystem.isSleepDisabled(pmsetOutput: ""))
    }

    func testRuleAllowsOnlyTheSwitch() {
        XCTAssertEqual(SleepSystem.ruleLine(user: "jo.doe"), "jo.doe ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1")
        for bad in ["", "-x", "a b", "ALL ALL", "a;b", "a'b", "дом\\jo", "a\nb"] {
            XCTAssertNil(SleepSystem.ruleLine(user: bad), bad)
            XCTAssertNil(SleepSystem.installCommand(user: bad), bad)
        }
    }

    /// In a folder of its own, without root: nothing near /etc/sudoers.d.
    func testInstallCommandWritesARuleVisudoAccepts() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("killtree-rule-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let command = try XCTUnwrap(SleepSystem.installCommand(user: "tester", folder: folder.path, setsOwner: false))
        XCTAssertEqual(Launchctl.run(executable: "/bin/sh", ["-c", command]).status, 0)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(names, ["killtree-lid-closed"], "the hidden temporary file is gone")
        let rule = folder.appendingPathComponent("killtree-lid-closed")
        XCTAssertEqual(try String(contentsOf: rule, encoding: .utf8), SleepSystem.ruleLine(user: "tester")! + "\n")
        XCTAssertEqual(Launchctl.run(executable: "/usr/sbin/visudo", ["-cf", rule.path]).status, 0)
    }

    func testInstallCommandSurvivesTheAdministratorEscaping() throws {
        // What runAsAdministrator hands to AppleScript, parsed back by `sh -n`.
        let command = try XCTUnwrap(SleepSystem.installCommand(user: "tester"))
        XCTAssertEqual(Launchctl.run(executable: "/bin/sh", ["-n", "-c", command]).status, 0)
    }

    func testAssertionComesAndGoes() throws {
        func listed() -> Bool { (Launchctl.run(executable: "/usr/bin/pmset", ["-g", "assertions"]).output ?? "").contains("K*llTree: Keep Awake") }
        let id = try XCTUnwrap(SleepSystem.takeAssertion())
        XCTAssertTrue(listed())
        IOPMAssertionRelease(id)
        XCTAssertFalse(listed())
    }
}

// MARK: - The panel, on the made-up Mac

@MainActor
final class DemoTests: XCTestCase {
    private func make() throws -> KillTreeDroplet {
        let droplet = KillTreeDroplet()
        try droplet.activate(host: .harness(dropletID: KillTreeDroplet.id, recorder: HarnessRecorder()))
        XCTAssertTrue(droplet.isDemo)
        return droplet
    }

    func testWhatTakesSomethingOverStartsOff() throws {
        let droplet = try make()
        XCTAssertFalse(droplet.guardsClosed)
        XCTAssertFalse(droplet.persistsAcrossRestart)
        XCTAssertFalse(droplet.includesSystem)
        XCTAssertFalse(droplet.includesServices)
        XCTAssertFalse(droplet.power.keepsAwake)
    }

    func testDemoRuleTouchesNothingReal() async throws {
        let droplet = try make()
        let before = SleepSystem.hasPasswordRule
        droplet.skipsPasswordBinding.wrappedValue = true
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(droplet.power.skipsPassword)
        XCTAssertEqual(SleepSystem.hasPasswordRule, before)
    }

    func testPairedHeightDoesNotFollowTheList() throws {
        let droplet = try make()
        let solo = droplet.widgetHeight
        droplet.setPaired(true)
        XCTAssertEqual(droplet.widgetHeight, KillTreeDroplet.pairedHeight)
        XCTAssertLessThan(droplet.widgetHeight, solo)
        droplet.openAlone()
        XCTAssertEqual(droplet.widgetHeight, solo, "opening alone goes back to the list's height")
    }

    func testOpenAloneNeedsItsCapability() throws {
        let manifest = try String(contentsOfFile: "../killtree/droplet.json", encoding: .utf8)
        XCTAssertTrue(manifest.contains("shelf-write"), "open(revealing:) is refused without it")
    }

    func testCloseAllNeedsAnOpenPanel() throws {
        let droplet = try make()
        droplet.selectTab(.terminal)
        droplet.closeAll()
        XCTAssertTrue(droplet.working.isEmpty)
    }

    func testCloseLeftoversLeavesOpenAppsAndWhatServesThem() async throws {
        let droplet = try make()
        droplet.selectTab(.apps)
        let keep = droplet.visibleGroups.filter(\.isAppRunning).map(\.id)
        droplet.setToolsOpen(true)
        droplet.closeAll()
        XCTAssertFalse(droplet.isToolsOpen)
        for id in keep { XCTAssertNil(droplet.working[id]) }
        try await Task.sleep(for: .seconds(1.6))
        for id in keep { XCTAssertTrue(droplet.visibleGroups.contains { $0.id == id }, id) }
    }

    func testStopAllLeavesServicesUnlessAsked() async throws {
        let droplet = try make()
        droplet.selectTab(.servers)
        let services = droplet.tasks(in: .servers).filter { $0.job != nil }.map(\.id)
        droplet.setToolsOpen(true)
        droplet.closeAll()
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertEqual(Set(droplet.tasks(in: .servers).map(\.id)), Set(services))
        droplet.setToolsOpen(true)
        XCTAssertFalse(droplet.canCloseAll)
        droplet.includesServicesBinding.wrappedValue = true
        XCTAssertEqual(droplet.canCloseAll, !services.isEmpty)
    }

    func testCloseAllEndsEveryTerminal() async throws {
        let droplet = try make()
        droplet.selectTab(.terminal)
        droplet.setToolsOpen(true)
        droplet.closeAll()
        try await Task.sleep(for: .seconds(1.4))
        XCTAssertTrue(droplet.tasks(in: .terminal).isEmpty)
    }

    func testRestoreRemovesTheRecord() throws {
        let droplet = try make()
        let closed = try XCTUnwrap(droplet.state.closed.first)
        droplet.restore(closed.id)
        XCTAssertFalse(droplet.state.closed.contains { $0.id == closed.id })
    }

    func testPanelFitsOnEveryList() throws {
        let droplet = try make()
        for category in Category.allCases {
            droplet.selectTab(category)
            droplet.setToolsOpen(false, animated: false)
            let closed = droplet.widgetHeight
            XCTAssertLessThanOrEqual(closed, 480)
            droplet.setToolsOpen(true, animated: false)
            let content = droplet.widgetHeight - KillTreeDroplet.hostInsets
            XCTAssertGreaterThanOrEqual(content, ToolsMetrics.panelHeight + ToolsMetrics.islandMargin, "\(category)")
            XCTAssertLessThanOrEqual(droplet.widgetHeight, 480)
        }
    }

    func testPanelShutsWithTheTabAndTheShelf() throws {
        let droplet = try make()
        droplet.selectTab(.apps)
        droplet.setToolsOpen(true, animated: false)
        droplet.selectTab(.servers)
        XCTAssertFalse(droplet.isToolsOpen)
        droplet.widgetAppeared()
        droplet.setToolsOpen(true, animated: false)
        droplet.widgetDisappeared()
        XCTAssertFalse(droplet.isToolsOpen)
    }

    func testDemoSwitchesTouchNothingReal() async throws {
        let droplet = try make()
        let before = SleepSystem.isSleepDisabled()
        droplet.setKeepsAwake(true)
        XCTAssertTrue(droplet.power.keepsAwake)
        XCTAssertFalse((Launchctl.run(executable: "/usr/bin/pmset", ["-g", "assertions"]).output ?? "").contains("K*llTree"))
        droplet.setLidClosed(true)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertTrue(droplet.power.lidClosed)
        XCTAssertEqual(SleepSystem.isSleepDisabled(), before)
        droplet.deactivate()
        XCTAssertFalse(droplet.power.keepsAwake)
    }
}

// MARK: - The real Mac, read only

/// Reads what is running and prints what the bulk buttons would touch.
/// Nothing here closes anything.
final class RealScanDryRun: XCTestCase {
    func testWhatTheBulkButtonsWouldTouch() {
        let scanner = ProcessScanner()
        let apps = AppDirectory.read(scanner: scanner)
        let processes = scanner.scan()
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }.map {
            RunningApp(pid: $0.processIdentifier, name: $0.localizedName ?? "App", bundlePath: $0.bundleURL?.path, isMenuBar: $0.activationPolicy == .accessory)
        }
        let catalog = LaunchCatalog.read(appBundles: apps.map(\.path) + running.compactMap(\.bundlePath))
        var input = GroupBuilder.Input(processes: processes, catalog: catalog, runningApps: running, installed: apps, excludedTeams: [], ownPID: getpid())
        input.ports = ProcessScanner.listeningPorts()
        let result = GroupBuilder.build(input, scanner: scanner)
        XCTAssertFalse(processes.isEmpty)
        for category in [Category.terminal, .servers] {
            for task in result.tasks where task.category == category {
                print("WOULD \(category): \(task.name) [\(task.processes.count)\(task.job != nil ? ", launchd" : "")]")
                XCTAssertFalse(task.processes.keys.contains { $0 <= 1 || $0 == getpid() })
            }
        }
    }
}
