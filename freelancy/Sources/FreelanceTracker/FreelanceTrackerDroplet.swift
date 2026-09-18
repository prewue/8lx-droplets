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
    case analytics
}

public enum PendingDeletion: Hashable, Sendable {
    case project(UUID)
    case session(UUID)
}

@MainActor
public final class FreelanceTrackerDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "freelance-tracker"

    static let widgetID: ShelfWidgetID = "tracker"

    private var host: DropletHost?

    @Published public private(set) var projects: [Project] = []

    @Published public private(set) var sessions: [WorkSession] = []

    @Published public private(set) var currentProjectID: UUID?

    @Published public private(set) var screen: TrackerScreen = .menu

    @Published public private(set) var editingProjectID: UUID?

    @Published public private(set) var analyticsProjectID: UUID?

    @Published public private(set) var pendingDeletion: PendingDeletion?

    @Published public private(set) var now = Date()

    private var ticker: Task<Void, Never>?
    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)

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
    }

    public func activate(host: DropletHost) throws {
        self.host = host
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
        ticker?.cancel()
        ticker = nil
        activitySubject.send(nil)
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
        show(projects.isEmpty ? .newProject : .timer)
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
        guard projects.contains(where: { $0.id == projectID }) else { return }
        let heightBefore = widgetHeight
        editingProjectID = projectID
        screen = .editProject
        refreshLayout(from: heightBefore)
    }

    public func showAnalytics(for projectID: UUID) {
        guard projects.contains(where: { $0.id == projectID }) else { return }
        analyticsProjectID = projectID
        show(.analytics)
    }

    public var editingProject: Project? {
        guard let editingProjectID else { return nil }
        return project(editingProjectID)
    }

    public func openSettings() {
        host?.workspace.openSettings()
    }

    @discardableResult
    public func createProject(rate: Double, currency: TrackerCurrency, color: ProjectColor) -> Project {
        let project = Project(
            name: "Project \(projects.count + 1)",
            rate: max(0, rate),
            currencyCode: currency.code,
            color: color
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

    public func updateProject(_ projectID: UUID, rate: Double, currency: TrackerCurrency, color: ProjectColor) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].rate = max(0, rate)
        projects[index].currencyCode = currency.code
        projects[index].color = color
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

    public func setCurrency(_ projectID: UUID, to currency: TrackerCurrency) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].currencyCode = currency.code
        save()
        publishActivity()
    }

    public func askToDelete(_ deletion: PendingDeletion) {
        pendingDeletion = deletion
    }

    public func cancelDeletion() {
        pendingDeletion = nil
    }

    public func confirmDeletion() {
        guard let pendingDeletion else { return }
        self.pendingDeletion = nil
        switch pendingDeletion {
        case .project(let id): deleteProject(id)
        case .session(let id): deleteSession(id)
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
        if editingProjectID == projectID {
            editingProjectID = nil
            if screen == .editProject { screen = .projects }
        }
        save()
        syncTicker()
        publishActivity()
        refreshLayout(from: heightBefore)
        host?.feedback.play(.tick)
    }

    @discardableResult
    public func newSession(on projectID: UUID) -> WorkSession? {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return nil }
        let moment = Date()
        let heightBefore = widgetHeight
        let runs = startsSessionsRunning
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
            newSession(on: projectID)
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
    static let screenSide: CGFloat = 10
    static let screenTop: CGFloat = 6
    static let screenBottom: CGFloat = 8
    static let navHeight: CGFloat = 28

    static let cardWidth: CGFloat = 176
    static let cardHeight: CGFloat = 82
    static let cardSpacing: CGFloat = 8

    static let timerRowHeight: CGFloat = 58

    static let formRowHeight: CGFloat = 24

    static let analyticsPageHeight: CGFloat = 112
    static let chartBarHeight: CGFloat = 52
    static let pageDotsHeight: CGFloat = 6

    var widgetHeight: CGFloat {
        let frame = Self.screenTop + Self.screenBottom
        let gap = DroppySpacing.sm
        switch screen {
        case .menu:
            return frame + 84

        case .timer:
            return frame + Self.navHeight + gap + Self.timerRowHeight + gap + 16
        case .projects, .sessions:
            return frame + Self.navHeight + gap + Self.cardHeight
        case .newProject, .editProject:
            return frame + Self.navHeight + 4 * (gap + Self.formRowHeight)
        case .analytics:
            return frame + Self.navHeight + DroppySpacing.lg + Self.analyticsPageHeight + DroppySpacing.md + Self.pageDotsHeight
        }
    }

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Freelancy",
                systemImage: "stopwatch.fill",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 420,
                    preferredPairedWidth: 210,
                    contentHeight: .fixed(widgetHeight)
                ),
                searchKeywords: ["time", "timer", "billing", "hourly", "rate", "money", "freelance", "invoice", "project"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        if context.isCompact, !context.isPreview, host?.environment.isHarness == false,
           screen != .timer, screen != .projects {
            Task { @MainActor [weak self] in self?.show(.timer) }
        }
        return AnyView(FreelanceTrackerWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
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
            SettingsSearchEntry(title: "Start new sessions running", keywords: ["session", "start", "auto", "timer", "paused"]),
            SettingsSearchEntry(title: "Show me the money", keywords: ["money", "amount", "time", "order", "swap", "first"])
        ]
    }
}
