import Combine
import DroppyKit
import SwiftUI

@objc(FreelanceTrackerPrincipal)
public final class FreelanceTrackerPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { FreelanceTrackerDroplet() }
}

public enum TrackerScreen: Hashable, Sendable {
    case menu
    case timer
    case projects
    case sessions
    case newProject
    case editProject
    case renameSession
    case analytics
}

public enum ProjectStep: Hashable, Sendable {
    case name
    case look
    case rate
    case currency
    case color
}

public struct SessionRename: Equatable, Sendable {
    public let sessionID: UUID
    public var name: String
}

public struct ProjectDraft: Equatable, Sendable {
    public var editingID: UUID?
    public var step: ProjectStep = .name
    public var name: String
    public var icon: ProjectIcon
    public var color: ProjectColor
    public var rate: Double
    public var currency: TrackerCurrency
    public var pendingCurrency: TrackerCurrency?
    public var pendingColor: ProjectColor?

    public var isEditing: Bool { editingID != nil }
}

public enum PendingConfirmation: Hashable, Sendable {
    case deleteProject(UUID)
    case deleteSession(UUID)
    case newSession(UUID)
    case switchProject(UUID)
}

@MainActor
public final class FreelanceTrackerDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "freelance-tracker"

    static let widgetID: ShelfWidgetID = "tracker"

    private var host: DropletHost?

    @Published public private(set) var projects: [Project] = []

    @Published public private(set) var sessions: [WorkSession] = []

    @Published public private(set) var currentProjectID: UUID?

    @Published public private(set) var screen: TrackerScreen = .menu {
        didSet {
            if oldValue != screen { syncShelfHold() }
        }
    }

    @Published public private(set) var draft: ProjectDraft?

    @Published public private(set) var sessionRename: SessionRename?

    private var holdsShelf = false


    @Published public private(set) var analyticsProjectID: UUID?

    @Published public private(set) var pendingConfirmation: PendingConfirmation?

    @Published public private(set) var freshSessionID: UUID?

    private var freshTask: Task<Void, Never>?

    @Published public private(set) var now = Date()

    private var ticker: Task<Void, Never>?
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    /// Tells a host that reads `ShelfWidgetDynamicLayoutProviding` to re-read the traits.
    private let layoutSubject = PassthroughSubject<ShelfWidgetID, Never>()
    /// Whether Droppy last mounted the widget in a grouped row. The descriptor has one height
    /// for both compositions and `currentLayoutTraits` gets no context, so the height follows
    /// the mount the host last asked for.
    private var mountedGrouped = false

    private enum Keys {
        static let projects = "projects"
        static let sessions = "workSessions"
        static let currentProject = "currentProject"
        static let defaultRate = "defaultRate"
        static let defaultCurrency = "defaultCurrency"
        static let pinsLiveActivity = "pinsLiveActivity"
        static let showsHUD = "showsHUD"
        static let moneyFirst = "moneyFirst"
        static let startsSessionsRunning = "startsSessionsRunning"
        static let asksBeforeNewSession = "asksBeforeNewSession"
        static let asksBeforeSwitching = "asksBeforeSwitching"
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        FlowFocus.requestKey = { [weak self] in self?.host?.shelf.requestKeyboardFocus() ?? false }
        load()
        if projects.isEmpty, host.environment.isHarness {
            seedDemoData()
        }
        screen = .menu
        now = Date()
        host.log.info("Freelancy activated with \(projects.count) project\(projects.count == 1 ? "" : "s"), \(sessions.count) session\(sessions.count == 1 ? "" : "s")")

        syncTicker()
        publishActivity()
    }

    public func deactivate() {
        FlowFocus.requestKey = nil
        if holdsShelf {
            _ = host?.shelf.setHoldsOpen(false)
            holdsShelf = false
        }
        freshTask?.cancel()
        freshTask = nil
        ticker?.cancel()
        ticker = nil
        activitySubject.send(nil)
        // Re-enabled, the droplet starts at the menu, not inside a flow or a question it left.
        draft = nil
        sessionRename = nil
        pendingConfirmation = nil
        freshSessionID = nil
        screen = .menu
        host = nil
    }

    public var currentProject: Project? {
        guard let currentProjectID else { return projects.first }
        return projects.first { $0.id == currentProjectID } ?? projects.first
    }

    public func currentSession(of projectID: UUID) -> WorkSession? {
        guard let project = project(projectID) else { return nil }
        if let id = project.currentSessionID, let session = sessions.first(where: { $0.id == id }) {
            return session
        }
        return sessions.first { $0.projectID == projectID }
    }

    public var runningSession: WorkSession? {
        sessions.first { $0.isRunning }
    }

    public func project(_ id: UUID) -> Project? {
        projects.first { $0.id == id }
    }

    public func session(_ id: UUID) -> WorkSession? {
        sessions.first { $0.id == id }
    }

    public func sessions(of projectID: UUID) -> [WorkSession] {
        sessions.filter { $0.projectID == projectID }
    }

    public func totalSeconds(of projectID: UUID) -> TimeInterval {
        sessions(of: projectID).reduce(0) { $0 + $1.duration(at: now) }
    }

    public var defaultRate: Double {
        host?.preferences.value(forKey: Keys.defaultRate, default: 50.0) ?? 50
    }

    public var defaultCurrency: TrackerCurrency {
        let code = host?.preferences.value(forKey: Keys.defaultCurrency, default: TrackerCurrency.usd.code)
        return TrackerCurrency.named(code ?? TrackerCurrency.usd.code)
    }

    public var pinsLiveActivity: Bool {
        host?.preferences.value(forKey: Keys.pinsLiveActivity, default: true) ?? true
    }

    public var showsHUD: Bool {
        host?.preferences.value(forKey: Keys.showsHUD, default: true) ?? true
    }

    public var defaultRateBinding: Binding<Double> {
        Binding(
            get: { self.defaultRate },
            set: { self.host?.preferences.setValue($0, forKey: Keys.defaultRate); self.objectWillChange.send() }
        )
    }

    public func setDefaultCurrency(_ currency: TrackerCurrency) {
        host?.preferences.setValue(currency.code, forKey: Keys.defaultCurrency)
        objectWillChange.send()
    }

    public var pinsLiveActivityBinding: Binding<Bool> {
        Binding(
            get: { self.pinsLiveActivity },
            set: {
                self.host?.preferences.setValue($0, forKey: Keys.pinsLiveActivity)
                self.objectWillChange.send()
                self.publishActivity()
            }
        )
    }

    public var moneyFirst: Bool {
        host?.preferences.value(forKey: Keys.moneyFirst, default: false) ?? false
    }

    public var startsSessionsRunning: Bool {
        host?.preferences.value(forKey: Keys.startsSessionsRunning, default: true) ?? true
    }

    public var startsSessionsRunningBinding: Binding<Bool> {
        Binding(
            get: { self.startsSessionsRunning },
            set: { self.host?.preferences.setValue($0, forKey: Keys.startsSessionsRunning); self.objectWillChange.send() }
        )
    }

    public var asksBeforeNewSession: Bool {
        host?.preferences.value(forKey: Keys.asksBeforeNewSession, default: true) ?? true
    }

    public var asksBeforeNewSessionBinding: Binding<Bool> {
        Binding(
            get: { self.asksBeforeNewSession },
            set: { self.host?.preferences.setValue($0, forKey: Keys.asksBeforeNewSession); self.objectWillChange.send() }
        )
    }

    public var asksBeforeSwitching: Bool {
        host?.preferences.value(forKey: Keys.asksBeforeSwitching, default: true) ?? true
    }

    public var asksBeforeSwitchingBinding: Binding<Bool> {
        Binding(
            get: { self.asksBeforeSwitching },
            set: { self.host?.preferences.setValue($0, forKey: Keys.asksBeforeSwitching); self.objectWillChange.send() }
        )
    }

    public var moneyFirstBinding: Binding<Bool> {
        Binding(
            get: { self.moneyFirst },
            set: { self.host?.preferences.setValue($0, forKey: Keys.moneyFirst); self.objectWillChange.send() }
        )
    }

    public var showsHUDBinding: Binding<Bool> {
        Binding(
            get: { self.showsHUD },
            set: { self.host?.preferences.setValue($0, forKey: Keys.showsHUD); self.objectWillChange.send() }
        )
    }

    public func show(_ target: TrackerScreen) {
        guard target != screen else { return }
        let heightBefore = widgetHeight
        screen = target
        refreshLayout(from: heightBefore)
    }

    public func openTimer() {
        if projects.isEmpty {
            startNewProject()
        } else {
            show(.timer)
        }
    }

    public var isInProjectFlow: Bool {
        screen == .newProject || screen == .editProject || screen == .renameSession
    }

    public func startRenamingSession(_ sessionID: UUID) {
        guard let session = session(sessionID) else { return }
        sessionRename = SessionRename(sessionID: sessionID, name: session.name)
        show(.renameSession)
    }

    public func updateSessionRename(_ name: String) {
        guard var rename = sessionRename, rename.name != name else { return }
        rename.name = name
        sessionRename = rename
    }

    public func commitSessionRename() {
        if let rename = sessionRename {
            renameSession(rename.sessionID, to: rename.name)
            host?.feedback.play(.success)
        }
        sessionRename = nil
        show(.sessions)
    }

    public func cancelSessionRename() {
        sessionRename = nil
        show(.sessions)
    }

    private func syncShelfHold() {
        let wants = isInProjectFlow
        guard wants != holdsShelf, let host else { return }
        holdsShelf = wants
        _ = host.shelf.setHoldsOpen(wants)
        publishLayoutChange()
    }

    public var draftPlaceholderName: String {
        "Project \(projects.count + 1)"
    }

    public func startNewProject() {
        draft = ProjectDraft(
            name: "",
            icon: .briefcase,
            color: ProjectColor.suggested(forProjectNumber: projects.count + 1),
            rate: defaultRate,
            currency: defaultCurrency
        )
        show(.newProject)
    }

    public func updateDraft(_ change: (inout ProjectDraft) -> Void) {
        guard var current = draft else { return }
        change(&current)
        if current != draft { draft = current }
    }

    public func setDraftStep(_ step: ProjectStep) {
        updateDraft {
            if step == .currency { $0.pendingCurrency = $0.currency }
            if step == .color { $0.pendingColor = $0.color }
            $0.step = step
        }
    }

    private func closeCurrencyPicker(applying: Bool) {
        updateDraft {
            if applying, let chosen = $0.pendingCurrency { $0.currency = chosen }
            $0.pendingCurrency = nil
            $0.step = .rate
        }
    }

    private func closeColorPicker(applying: Bool) {
        updateDraft {
            if applying, let chosen = $0.pendingColor { $0.color = chosen }
            $0.pendingColor = nil
            $0.step = .look
        }
    }

    public func advanceDraft() {
        guard let draft else { return }
        switch draft.step {
        case .name: setDraftStep(.look)
        case .look: setDraftStep(.rate)
        case .rate: commitDraft()
        case .currency: closeCurrencyPicker(applying: true)
        case .color: closeColorPicker(applying: true)
        }
    }

    public func backInDraft() {
        guard let draft else {
            show(projects.isEmpty ? .menu : .projects)
            return
        }
        switch draft.step {
        case .currency: closeCurrencyPicker(applying: false)
        case .color: closeColorPicker(applying: false)
        case .rate: setDraftStep(.look)
        case .look: setDraftStep(.name)
        case .name:
            let target: TrackerScreen = draft.isEditing || !projects.isEmpty ? .projects : .menu
            show(target)
            self.draft = nil
        }
    }

    public func commitDraft() {
        guard let draft else { return }
        if let id = draft.editingID {
            updateProject(id, name: draft.name, rate: draft.rate, currency: draft.currency, color: draft.color, icon: draft.icon)
        } else {
            createProject(name: draft.name, rate: draft.rate, currency: draft.currency, color: draft.color, icon: draft.icon)
        }
        self.draft = nil
    }

    public func open(_ projectID: UUID) {
        guard projects.contains(where: { $0.id == projectID }) else { return }
        let heightBefore = widgetHeight
        currentProjectID = projectID
        screen = .timer
        save()
        refreshLayout(from: heightBefore)
    }

    public func edit(_ projectID: UUID) {
        guard let project = project(projectID) else { return }
        draft = ProjectDraft(
            editingID: projectID,
            name: project.name,
            icon: project.icon,
            color: project.color,
            rate: project.rate,
            currency: project.currency
        )
        show(.editProject)
    }

    public func showAnalytics(for projectID: UUID) {
        guard projects.contains(where: { $0.id == projectID }) else { return }
        analyticsProjectID = projectID
        show(.analytics)
    }

    public func openSettings() {
        host?.workspace.openSettings()
    }

    @discardableResult
    public func createProject(name: String, rate: Double, currency: TrackerCurrency, color: ProjectColor, icon: ProjectIcon) -> Project {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(
            name: trimmed.isEmpty ? draftPlaceholderName : trimmed,
            rate: max(0, rate),
            currencyCode: currency.code,
            color: color,
            icon: icon
        )
        let heightBefore = widgetHeight
        projects.insert(project, at: 0)
        currentProjectID = project.id
        screen = .timer
        save()
        refreshLayout(from: heightBefore)
        host?.feedback.play(.success)
        return project
    }

    public func rename(_ projectID: UUID, to name: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects[index].name = trimmed
        save()
        publishActivity()
    }

    public func setRate(_ projectID: UUID, to rate: Double) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].rate = max(0, rate)
        save()
        publishActivity()
    }

    public func updateProject(_ projectID: UUID, name: String, rate: Double, currency: TrackerCurrency, color: ProjectColor, icon: ProjectIcon) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { projects[index].name = trimmed }
        projects[index].rate = max(0, rate)
        projects[index].currencyCode = currency.code
        projects[index].color = color
        projects[index].icon = icon
        save()
        publishActivity()
        host?.feedback.play(.success)
        show(.projects)
    }

    public func setColor(_ projectID: UUID, to color: ProjectColor) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].color = color
        save()
    }

    public func setIcon(_ projectID: UUID, to icon: ProjectIcon) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].icon = icon
        save()
    }

    public func setCurrency(_ projectID: UUID, to currency: TrackerCurrency) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].currencyCode = currency.code
        save()
        publishActivity()
    }

    public func ask(_ confirmation: PendingConfirmation) {
        pendingConfirmation = confirmation
    }

    public func cancelConfirmation() {
        pendingConfirmation = nil
    }

    public func confirmPending() {
        guard let pendingConfirmation else { return }
        self.pendingConfirmation = nil
        switch pendingConfirmation {
        case .deleteProject(let id):
            deleteProject(id)
        case .deleteSession(let id):
            deleteSession(id)
        case .newSession(let id):
            if let session = newSession(on: id) {
                flashFreshSession(session.id)
            }
        case .switchProject(let id):
            open(id)
        }
    }

    public func requestNewSession(on projectID: UUID) {
        if asksBeforeNewSession {
            ask(.newSession(projectID))
        } else if let session = newSession(on: projectID) {
            flashFreshSession(session.id)
        }
    }

    public func requestOpen(_ projectID: UUID) {
        if asksBeforeSwitching,
           let running = runningSession,
           running.projectID != projectID,
           projectID != currentProject?.id {
            ask(.switchProject(projectID))
        } else {
            open(projectID)
        }
    }

    private func flashFreshSession(_ id: UUID) {
        freshTask?.cancel()
        freshSessionID = id
        freshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, let self else { return }
            withAnimation(DroppyAnimation.state) { self.freshSessionID = nil }
        }
    }

    public func deleteProject(_ projectID: UUID) {
        let heightBefore = widgetHeight
        projects.removeAll { $0.id == projectID }
        sessions.removeAll { $0.projectID == projectID }
        if currentProjectID == projectID {
            currentProjectID = projects.first?.id
        }
        if projects.isEmpty, screen == .projects {
            screen = .menu
        }
        if draft?.editingID == projectID {
            draft = nil
            if screen == .editProject { screen = .projects }
        }
        save()
        syncTicker()
        publishActivity()
        refreshLayout(from: heightBefore)
        host?.feedback.play(.tick)
    }

    @discardableResult
    /// Starts a new session on the project. `running` overrides "Start new sessions running":
    /// Start on a project with no session means start, so it passes `true`.
    public func newSession(on projectID: UUID, running: Bool? = nil) -> WorkSession? {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let moment = Date()
        let heightBefore = widgetHeight
        let runs = running ?? startsSessionsRunning
        if runs { pauseEverything(at: moment) }
        let count = sessions(of: projectID).count
        let session = WorkSession(projectID: projectID, name: "Session \(count + 1)", createdAt: moment, activeSince: runs ? moment : nil)
        sessions.insert(session, at: 0)
        projects[index].currentSessionID = session.id
        currentProjectID = projectID
        screen = .timer
        now = moment
        save()
        syncTicker()
        publishActivity()
        refreshLayout(from: heightBefore)
        host?.feedback.play(.success)
        if runs {
            presentHUD(glyph: "play.fill", trailing: projects[index].formattedRate, label: "New session on \(projects[index].name)")
        }
        return session
    }

    public func togglePause(_ projectID: UUID) {
        guard let project = project(projectID) else { return }
        guard let current = currentSession(of: projectID),
              let index = sessions.firstIndex(where: { $0.id == current.id }) else {
            // Start with nothing to resume: the session it makes runs, whatever the preference.
            newSession(on: projectID, running: true)
            return
        }
        let moment = Date()
        if current.isRunning {
            sessions[index].accumulated += max(0, moment.timeIntervalSince(current.activeSince ?? moment))
            sessions[index].activeSince = nil
            let earned = project.formattedEarnings(for: sessions[index].duration(at: moment), compact: true)
            presentHUD(glyph: "pause.fill", trailing: earned, label: "Paused \(project.name), \(earned)")
        } else {
            pauseEverything(at: moment)
            sessions[index].activeSince = moment
            presentHUD(glyph: "play.fill", trailing: project.formattedRate, label: "Resumed \(project.name)")
        }
        now = moment
        save()
        syncTicker()
        publishActivity()
        host?.feedback.play(.tick)
    }

    private func pauseEverything(at moment: Date) {
        for index in sessions.indices where sessions[index].isRunning {
            sessions[index].accumulated += max(0, moment.timeIntervalSince(sessions[index].activeSince ?? moment))
            sessions[index].activeSince = nil
        }
    }

    public func select(_ sessionID: UUID) {
        guard let session = session(sessionID),
              let index = projects.firstIndex(where: { $0.id == session.projectID }) else { return }
        let heightBefore = widgetHeight
        projects[index].currentSessionID = sessionID
        currentProjectID = session.projectID
        screen = .timer
        save()
        refreshLayout(from: heightBefore)
    }

    public func renameSession(_ sessionID: UUID, to name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sessions[index].name = trimmed
        save()
    }

    public func setDuration(of sessionID: UUID, seconds: TimeInterval) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }), !sessions[index].isRunning else { return }
        sessions[index].accumulated = max(0, seconds)
        now = Date()
        save()
        host?.feedback.play(.tick)
    }

    public func deleteSession(_ sessionID: UUID) {
        guard let session = session(sessionID) else { return }
        if sessionRename?.sessionID == sessionID {
            sessionRename = nil
            if screen == .renameSession { screen = .sessions }
        }
        let heightBefore = widgetHeight
        sessions.removeAll { $0.id == sessionID }
        if let index = projects.firstIndex(where: { $0.id == session.projectID }),
           projects[index].currentSessionID == sessionID {
            projects[index].currentSessionID = sessions.first { $0.projectID == session.projectID }?.id
        }
        save()
        syncTicker()
        publishActivity()
        refreshLayout(from: heightBefore)
        host?.feedback.play(.tick)
    }

    private func syncTicker() {
        let shouldTick = runningSession != nil
        if shouldTick, ticker == nil {
            ticker = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    let interval = Date().timeIntervalSinceReferenceDate
                    let wait = interval.rounded(.up) - interval
                    try? await Task.sleep(for: .seconds(max(wait, 0.05)))
                    guard !Task.isCancelled, let self else { return }
                    self.tick()
                }
            }
        } else if !shouldTick, let ticker {
            ticker.cancel()
            self.ticker = nil
        }
    }

    private func tick() {
        now = Date()
        publishActivity()
    }

    private func load() {
        guard let host else { return }
        projects = host.preferences.value(forKey: Keys.projects, as: [Project].self) ?? []
        sessions = host.preferences.value(forKey: Keys.sessions, as: [WorkSession].self) ?? []
        sessions.removeAll { session in !projects.contains { $0.id == session.projectID } }
        if let raw = host.preferences.value(forKey: Keys.currentProject, as: String.self) {
            currentProjectID = UUID(uuidString: raw)
        }
        if currentProjectID == nil || !projects.contains(where: { $0.id == currentProjectID }) {
            currentProjectID = projects.first?.id
        }
    }

    private func save() {
        guard let host else { return }
        host.preferences.setValue(projects, forKey: Keys.projects)
        host.preferences.setValue(sessions, forKey: Keys.sessions)
        host.preferences.setValue(currentProjectID?.uuidString, forKey: Keys.currentProject)
    }

    private func refreshLayout(from previousHeight: CGFloat) {
        guard widgetHeight != previousHeight else { return }
        publishLayoutChange()
    }

    /// Asks the host to re-read the widget's traits: through the dynamic-layout publisher on
    /// hosts that read it (DroppyKit 1.20.0 and later) and `invalidateLayout` on the rest.
    private func publishLayoutChange() {
        layoutSubject.send(Self.widgetID)
        host?.shelf.invalidateLayout(for: Self.widgetID)
    }

    private func seedDemoData() {
        let moment = Date()
        let acme = Project(name: "Acme redesign", rate: 60, currencyCode: "USD", color: .cyan)
        let blog = Project(name: "Blog copy", rate: 40, currencyCode: "EUR", color: .orange)
        let icons = Project(name: "App icon set", rate: 3500, currencyCode: "RUB", color: .purple)
        let running = WorkSession(projectID: acme.id, name: "Checkout flow", createdAt: moment.addingTimeInterval(-3600), accumulated: 12 * 60 + 3, activeSince: moment.addingTimeInterval(-(11 * 60 + 41)))
        sessions = [
            running,
            WorkSession(projectID: acme.id, name: "Wireframes", createdAt: moment.addingTimeInterval(-26 * 3600), accumulated: 1 * 3600 + 50 * 60),
            WorkSession(projectID: blog.id, name: "Session 1", createdAt: moment.addingTimeInterval(-6 * 3600), accumulated: 48 * 60),
            WorkSession(projectID: acme.id, name: "Session 1", createdAt: moment.addingTimeInterval(-50 * 3600), accumulated: 2 * 3600 + 5 * 60),
            WorkSession(projectID: icons.id, name: "Session 1", createdAt: moment.addingTimeInterval(-70 * 3600), accumulated: 5 * 3600)
        ]
        projects = [
            Project(id: acme.id, name: acme.name, rate: acme.rate, currencyCode: acme.currencyCode, color: acme.color, currentSessionID: running.id),
            blog,
            icons
        ]
        currentProjectID = acme.id
        save()
    }

    @discardableResult
    public func exportCSV(projectID: UUID) -> URL? {
        guard let host, let project = project(projectID) else { return nil }
        let text = TrackerCSV.render(projects: [project], sessions: sessions(of: projectID), now: Date())
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let safeName = project.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = "\(safeName) \(stamp).csv"
        var folders = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        folders.append(host.environment.containerDirectory)
        for folder in folders {
            let url = folder.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
                host.log.info("wrote \(url.path)")
                host.workspace.revealInFinder(url)
                host.feedback.play(.success)
                presentHUD(glyph: "arrow.down.doc", trailing: "CSV saved", label: "CSV saved to \(folder.lastPathComponent)")
                return url
            } catch {
                host.log.error("could not write \(url.path): \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func presentHUD(glyph: String, trailing: String, label: String) {
        guard let host, showsHUD else { return }
        let request = DropletHUDRequest(
            id: "freelance-tracker.status",
            duration: 2.0,
            priority: .normal,
            accessibilityLabel: label
        ) {
            HStack(spacing: 0) {
                Image(systemName: glyph)
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                Spacer(minLength: 0)
                Text(verbatim: trailing)
                    .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        }

        _ = host.hud.present(request)
    }
}

extension FreelanceTrackerDroplet: ShelfWidgetProviding {
    /// The height `context.contentInsets` takes: 8 top and bottom under the host's
    /// 18pt card corner, none on a solo island card. The height budgets the larger.
    static let hostInsets: CGFloat = DroppySpacing.sm * 2
    static let navHeight: CGFloat = 28

    static let cardWidth: CGFloat = 176
    /// The card row's share of the Projects and Sessions screens. Both screens come to the
    /// timer's height, so moving between them never resizes the shelf; the cards fill it.
    static let cardRowHeight: CGFloat = 90
    static let cardSpacing: CGFloat = 12

    static let timerRowHeight: CGFloat = 58

    /// The widget in a grouped row: the paired timer's badge, clock and bottom row (94) and the
    /// host's insets. The paired lists, the empty state and a compact question fit in it too.
    static let groupedHeight: CGFloat = hostInsets + 94

    /// The start screen's content: the logo and its orbit, the greeting, two lines, the button.
    static let startScreenHeight: CGFloat = 191

    static let flowBodyHeight: CGFloat = 80
    static let flowActionHeight: CGFloat = 28

    static let analyticsPageHeight: CGFloat = 112
    static let chartBarHeight: CGFloat = 56
    static let pageDotsHeight: CGFloat = 6
    static let pageDotsGap: CGFloat = 16

    var widgetHeight: CGFloat {
        // A grouped row shares one height with its neighbours: the compact compositions all fit
        // in `groupedHeight`, whatever screen the solo widget was on.
        if mountedGrouped { return Self.groupedHeight }
        let frame = Self.hostInsets
        let gap = DroppySpacing.sm
        switch screen {
        case .menu:
            // With no projects the menu is the start screen instead (`StartScreen`).
            return frame + (projects.isEmpty ? Self.startScreenHeight : 84)

        case .timer:
            // A timer with no project to show is the start screen (`NoProjectScreen`).
            if currentProject == nil { return frame + Self.startScreenHeight }
            return frame + Self.navHeight + DroppySpacing.md + Self.timerRowHeight + DroppySpacing.md + 16
        case .projects, .sessions:
            return frame + Self.navHeight + gap + Self.cardRowHeight
        case .newProject, .editProject, .renameSession:
            return frame + Self.navHeight + DroppySpacing.md + Self.flowBodyHeight + DroppySpacing.md + Self.flowActionHeight
        case .analytics:
            return frame + Self.navHeight + DroppySpacing.xl + Self.analyticsPageHeight + Self.pageDotsGap + Self.pageDotsHeight
        }
    }

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Freelancy",
                systemImage: "stopwatch.fill",
                layoutTraits: layoutTraits,
                focusPolicy: isInProjectFlow ? .keyboardFocusable : .none,
                searchKeywords: ["time", "timer", "billing", "hourly", "rate", "money", "freelance", "invoice", "project"]
            )
        ]
    }

    var layoutTraits: ShelfWidgetLayoutTraits {
        ShelfWidgetLayoutTraits(
            preferredSoloWidth: 420,
            preferredPairedWidth: 210,
            contentHeight: .fixed(widgetHeight)
        )
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        if !context.isPreview, host?.environment.isHarness == false {
            let grouped = context.isCompact
            // A grouped row shows the paired timer, never a solo-only screen, so a flow or the
            // analytics left open goes back to the timer. Not with no projects: there is no
            // timer then, and the solo widget shows the start screen.
            let leavesSoloScreen = grouped && !projects.isEmpty
                && screen != .timer && screen != .projects && screen != .sessions
            if grouped != mountedGrouped || leavesSoloScreen {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if grouped != self.mountedGrouped {
                        self.mountedGrouped = grouped
                        self.publishLayoutChange()
                    }
                    if leavesSoloScreen { self.show(.timer) }
                }
            }
        }
        return AnyView(FreelanceTrackerWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }

    /// Shows the widget alone on the shelf, from the grouped row's empty state.
    public func revealAlone() {
        _ = host?.shelf.open(revealing: Self.widgetID)
    }
}

extension FreelanceTrackerDroplet: ShelfWidgetDynamicLayoutProviding {
    /// The traits as they are now, for a host that asks when it sizes the shelf (on open, not
    /// only after an invalidation). Cheap: it is the descriptor's own numbers.
    public func currentLayoutTraits(for id: ShelfWidgetID) -> ShelfWidgetLayoutTraits? {
        id == Self.widgetID ? layoutTraits : nil
    }

    public var shelfWidgetLayoutInvalidationPublisher: AnyPublisher<ShelfWidgetID, Never> {
        layoutSubject.eraseToAnyPublisher()
    }
}

extension FreelanceTrackerDroplet: LiveActivityProviding {
    public var liveActivityState: AnyPublisher<LiveActivityState?, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    public func liveActivitySeatDidChange(_ seat: DropletLiveActivitySeat) {
        host?.log.debug("live activity seat is now \(seat)")
    }

    public func makeCompactLeading() -> AnyView {
        AnyView(CompactClockView(droplet: self))
    }

    public func makeCompactTrailing() -> AnyView {
        AnyView(CompactMoneyView(droplet: self))
    }

    public func makeExpanded(context: LiveActivityContext) -> AnyView {
        AnyView(EmptyView())
    }

    var compactClock: String {
        guard let running = runningSession else { return "" }
        return TrackerClock.compact(running.duration(at: now))
    }

    var compactProjectColor: Color {
        guard let running = runningSession, let project = project(running.projectID) else {
            return AdaptiveColors.notchSurfaceSecondaryText
        }
        return project.color.color
    }

    var compactEarnings: String {
        guard let running = runningSession, let project = project(running.projectID) else { return "" }
        return project.formattedEarnings(for: running.duration(at: now), compact: true)
    }

    private func publishActivity() {
        guard let running = runningSession, let project = project(running.projectID) else {
            activitySubject.send(nil)
            return
        }
        let elapsed = TrackerClock.full(running.duration(at: now))
        let earned = project.formattedEarnings(for: running.duration(at: now))
        activitySubject.send(
            LiveActivityState(
                priority: 400,
                accessibilityTitle: "\(project.name), \(elapsed), \(earned)",
                isInteractive: false,
                joinsPersistentActivitySet: pinsLiveActivity,
                compactPresentation: nil,
                expandedWidgetID: Self.widgetID.rawValue
            )
        )
    }
}

private struct CompactClockView: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        RollingDigits(
            droplet.compactClock,
            font: .system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .medium, design: .rounded),
            color: droplet.compactProjectColor
        )
    }
}

private struct CompactMoneyView: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        RollingDigits(
            droplet.compactEarnings,
            font: .system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold, design: .rounded),
            color: AdaptiveColors.notchSurfacePrimaryText
        )
    }
}

extension FreelanceTrackerDroplet: HUDPresenting {}

extension FreelanceTrackerDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(FreelanceTrackerSettings(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Hourly rate", keywords: ["rate", "price", "money", "billing"]),
            SettingsSearchEntry(title: "Currency", keywords: ["dollar", "euro", "ruble", "currency"]),
            SettingsSearchEntry(title: "Projects", keywords: ["project", "session", "name", "rename"]),
            SettingsSearchEntry(title: "Keep the tracker in the notch", keywords: ["notch", "live activity", "pin"]),
            SettingsSearchEntry(title: "Ask before starting a new session", keywords: ["confirm", "question", "session", "new", "ask"]),
            SettingsSearchEntry(title: "Ask before switching projects", keywords: ["confirm", "question", "project", "switch", "ask"]),
            SettingsSearchEntry(title: "Start new sessions running", keywords: ["session", "start", "auto", "timer", "paused"]),
            SettingsSearchEntry(title: "Show me the money", keywords: ["money", "amount", "time", "order", "swap", "first"])
        ]
    }
}
