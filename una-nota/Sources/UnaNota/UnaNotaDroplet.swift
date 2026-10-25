import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's `NSPrincipalClass`.
/// It only creates the droplet: it runs before the host is ready.
@objc(UnaNotaPrincipal)
public final class UnaNotaPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { UnaNotaDroplet() }
}

public enum NotaScreen: Hashable, Sendable {
    case list
    case detail(UUID)
    case newReminder
    case editReminder
}

public enum ReminderStep: Hashable, Sendable {
    case date, time, text

    /// The day and the time share one view, which plays its own transition between them.
    public enum Group: Hashable, Sendable {
        case pick, text
    }

    public var group: Group {
        switch self {
        case .date, .time: .pick
        case .text: .text
        }
    }
}

struct ReminderDraft: Equatable, Sendable {
    /// The reminder being edited, nil for a new one.
    var id: UUID?
    var step: ReminderStep = .date
    var title = ""
    var note = ""
    var day: DayStamp
    var hour: Int
    var minute: Int
    var hue: Double
    var tone: Double = NotaColor.defaultTone
    /// Set when the day or time step was opened from the pills on the text step, so
    /// Continue and Back both return there.
    var returnsToText = false
    /// The colour before the spectrum opened, while it is open; Back puts it back.
    var colorBeforePick: (hue: Double, tone: Double)?

    var picksColor: Bool { colorBeforePick != nil }
    var color: Color { NotaColor.color(hue: hue, tone: tone) }

    static func == (lhs: ReminderDraft, rhs: ReminderDraft) -> Bool {
        lhs.id == rhs.id && lhs.step == rhs.step && lhs.title == rhs.title && lhs.note == rhs.note
            && lhs.day == rhs.day && lhs.hour == rhs.hour && lhs.minute == rhs.minute
            && lhs.hue == rhs.hue && lhs.tone == rhs.tone && lhs.returnsToText == rhs.returnsToText
            && lhs.colorBeforePick?.hue == rhs.colorBeforePick?.hue && lhs.colorBeforePick?.tone == rhs.colorBeforePick?.tone
    }

    var isEditing: Bool { id != nil }
}

/// Una Nota: reminders, and only them.
@MainActor
public final class UnaNotaDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "una-nota"

    static let widgetID: ShelfWidgetID = "reminders"

    private var host: DropletHost?

    @Published private(set) var reminders: [Reminder] = []

    @Published public private(set) var screen: NotaScreen = .list {
        didSet {
            if oldValue != screen { syncShelfHold() }
        }
    }

    @Published private(set) var draft: ReminderDraft?

    /// The reminder a delete question is up for.
    @Published public private(set) var pendingDelete: UUID?

    /// The reminder just created, for the "created" line.
    @Published public private(set) var freshID: UUID?

    /// The reminder whose note is unfolded in the list.
    @Published public private(set) var expandedID: UUID?

    /// The reminder just ticked, drawn done in place for a beat before it drops down the list.
    @Published public private(set) var completingID: UUID?
    private var completingTask: Task<Void, Never>?

    @Published public private(set) var now = Date()

    private var holdsShelf = false
    private var ticker: Task<Void, Never>?
    private var freshTask: Task<Void, Never>?
    /// Tells the host to re-read the widget size.
    private let layoutSubject = PassthroughSubject<ShelfWidgetID, Never>()
    /// Whether the widget sits in a row with other widgets.
    private var isInGroupedRow = false

    private enum Keys {
        static let reminders = "reminders"
        static let showsDueStrip = "showsDueStrip"
        static let keepsCompleted = "keepsCompleted"
    }

    public func activate(host: DropletHost) throws {
        self.host = host
        FlowFocus.requestKey = { [weak self] in self?.host?.shelf.requestKeyboardFocus() ?? false }
        load()
        if reminders.isEmpty, Self.showsDemoData(in: host) {
            seedDemoData()
        }
        screen = .list
        now = Date()
        host.log.info("Una Nota activated with \(reminders.count) reminder\(reminders.count == 1 ? "" : "s")")
        startTicker()
        announceDue()
    }

    public func deactivate() {
        FlowFocus.requestKey = nil
        if holdsShelf {
            _ = host?.shelf.setHoldsOpen(false)
            holdsShelf = false
        }
        ticker?.cancel()
        ticker = nil
        freshTask?.cancel()
        freshTask = nil
        completingTask?.cancel()
        completingTask = nil
        completingID = nil
        draft = nil
        pendingDelete = nil
        freshID = nil
        expandedID = nil
        screen = .list
        host = nil
    }

    // MARK: - Reading

    var today: DayStamp { DayStamp.today(now) }

    func reminder(_ id: UUID) -> Reminder? {
        reminders.first { $0.id == id }
    }

    /// Open reminders by day, then the completed ones when they are kept.
    var listed: [Reminder] {
        let open = reminders.filter { !$0.isDone }.sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
        guard keepsCompleted else { return open }
        let done = reminders.filter { $0.isDone }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        return open + done
    }

    public var openCount: Int { reminders.filter { !$0.isDone }.count }

    public var showsDueStrip: Bool {
        host?.preferences.value(forKey: Keys.showsDueStrip, default: true) ?? true
    }

    public var showsDueStripBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.showsDueStrip ?? true },
            set: { [weak self] value in self?.host?.preferences.setValue(value, forKey: Keys.showsDueStrip) }
        )
    }

    public var keepsCompleted: Bool {
        host?.preferences.value(forKey: Keys.keepsCompleted, default: true) ?? true
    }

    public var keepsCompletedBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.keepsCompleted ?? true },
            set: { [weak self] value in
                guard let self else { return }
                let heightBefore = self.widgetHeight
                self.host?.preferences.setValue(value, forKey: Keys.keepsCompleted)
                if !value {
                    self.reminders.removeAll { $0.isDone }
                    self.save()
                }
                self.objectWillChange.send()
                self.refreshLayout(from: heightBefore)
            }
        )
    }

    // MARK: - Screens

    public func show(_ target: NotaScreen) {
        guard target != screen else { return }
        let heightBefore = widgetHeight
        screen = target
        refreshLayout(from: heightBefore)
    }

    public func open(_ id: UUID) {
        guard reminder(id) != nil else { return }
        show(.detail(id))
    }

    public func openSettings() {
        _ = host?.workspace.openSettings()
    }

    var isInFlow: Bool {
        screen == .newReminder || screen == .editReminder
    }

    private func syncShelfHold() {
        let wants = isInFlow
        guard wants != holdsShelf, let host else { return }
        holdsShelf = wants
        _ = host.shelf.setHoldsOpen(wants)
        publishLayoutChange()
    }

    // MARK: - Flow

    public func startNewReminder() {
        let heightBefore = widgetHeight
        pendingDelete = nil
        // A new reminder starts at the next whole hour.
        let hour = min(Calendar.current.component(.hour, from: now) + 1, 23)
        draft = ReminderDraft(day: today, hour: hour, minute: 0, hue: NotaColor.defaultHue)
        screen = .newReminder
        refreshLayout(from: heightBefore)
    }

    public func edit(_ id: UUID) {
        guard let reminder = reminder(id) else { return }
        let heightBefore = widgetHeight
        pendingDelete = nil
        draft = ReminderDraft(id: id, title: reminder.title, note: reminder.note, day: reminder.day, hour: reminder.hour, minute: reminder.minute, hue: reminder.hue, tone: reminder.tone)
        screen = .editReminder
        refreshLayout(from: heightBefore)
    }

    func updateDraft(_ change: (inout ReminderDraft) -> Void) {
        guard var draft else { return }
        change(&draft)
        draft.day = draft.day.clamped
        if draft != self.draft { self.draft = draft }
    }

    public func advanceDraft() {
        guard let draft else { return }
        if draft.picksColor {
            // Choose: keep the colour, close the spectrum.
            updateDraft { $0.colorBeforePick = nil }
            return
        }
        if draft.returnsToText, draft.step == .date || draft.step == .time {
            updateDraft {
                $0.returnsToText = false
                $0.step = .text
            }
            return
        }
        switch draft.step {
        case .date: setDraftStep(.time)
        case .time: setDraftStep(.text)
        case .text: commitDraft()
        }
    }

    public func backInDraft() {
        guard let draft else { return }
        if let before = draft.colorBeforePick {
            // Back: the colour from before the spectrum opened.
            updateDraft {
                $0.hue = before.hue
                $0.tone = before.tone
                $0.colorBeforePick = nil
            }
            return
        }
        if draft.returnsToText, draft.step == .date || draft.step == .time {
            updateDraft {
                $0.returnsToText = false
                $0.step = .text
            }
            return
        }
        switch draft.step {
        case .date: leaveDraft()
        case .time: setDraftStep(.date)
        case .text: setDraftStep(.time)
        }
    }

    /// Opens the spectrum over the text step.
    public func startPickingColor() {
        updateDraft { draft in
            guard draft.colorBeforePick == nil else { return }
            draft.colorBeforePick = (draft.hue, draft.tone)
        }
    }

    /// Opens the day or the time from the pills on the text step.
    public func revisit(_ step: ReminderStep) {
        guard step == .date || step == .time else { return }
        updateDraft {
            $0.returnsToText = true
            $0.step = step
        }
    }

    private func setDraftStep(_ step: ReminderStep) {
        updateDraft { $0.step = step }
    }

    private func leaveDraft() {
        let returnScreen: NotaScreen = draft?.id.map { .detail($0) } ?? .list
        draft = nil
        show(returnScreen)
    }

    private func commitDraft() {
        guard let draft else { return }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let heightBefore = widgetHeight
        self.draft = nil
        if let id = draft.id, let index = reminders.firstIndex(where: { $0.id == id }) {
            reminders[index].title = title.isEmpty ? "Reminder" : title
            reminders[index].note = note
            if reminders[index].day != draft.day || reminders[index].hour != draft.hour || reminders[index].minute != draft.minute {
                reminders[index].day = draft.day
                reminders[index].hour = draft.hour
                reminders[index].minute = draft.minute
                reminders[index].announcedOn = nil
            }
            reminders[index].hue = draft.hue
            reminders[index].tone = draft.tone
            save()
            host?.feedback.play(.success)
            screen = .detail(id)
        } else {
            let reminder = Reminder(title: title.isEmpty ? "Reminder" : title, note: note, day: draft.day, hour: draft.hour, minute: draft.minute, hue: draft.hue, tone: draft.tone)
            reminders.append(reminder)
            save()
            host?.feedback.play(.success)
            screen = .list
            showCreated(reminder.id)
        }
        refreshLayout(from: heightBefore)
        announceDue()
    }

    private func showCreated(_ id: UUID) {
        freshTask?.cancel()
        freshID = id
        freshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.freshID = nil
        }
    }

    // MARK: - Changing

    /// Ticks a reminder: it darkens and strikes through where it is, then drops down the list.
    public func complete(_ id: UUID) {
        guard let reminder = reminder(id), !reminder.isDone, completingID != id else { return }
        completingTask?.cancel()
        completingID = id
        host?.feedback.play(.success)
        completingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let self, self.completingID == id else { return }
            self.completingID = nil
            self.toggleDone(id, announces: false)
        }
    }

    public func toggleDone(_ id: UUID, announces: Bool = true) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let heightBefore = widgetHeight
        if reminders[index].isDone {
            reminders[index].completedAt = nil
        } else {
            reminders[index].completedAt = now
            if announces { host?.feedback.play(.success) }
            if !keepsCompleted {
                reminders.remove(at: index)
                if screen == .detail(id) { screen = .list }
            }
        }
        save()
        refreshLayout(from: heightBefore)
    }

    /// Unfolds a reminder's note in the list, or folds it.
    public func toggleNote(_ id: UUID) {
        let heightBefore = widgetHeight
        expandedID = expandedID == id ? nil : id
        refreshLayout(from: heightBefore)
    }

    public func askToDelete(_ id: UUID) {
        guard reminder(id) != nil else { return }
        let heightBefore = widgetHeight
        pendingDelete = id
        refreshLayout(from: heightBefore)
    }

    public func cancelDelete() {
        let heightBefore = widgetHeight
        pendingDelete = nil
        refreshLayout(from: heightBefore)
    }

    public func confirmDelete() {
        guard let id = pendingDelete else { return }
        pendingDelete = nil
        delete(id)
    }

    public func delete(_ id: UUID) {
        let heightBefore = widgetHeight
        reminders.removeAll { $0.id == id }
        if expandedID == id { expandedID = nil }
        if screen == .detail(id) { screen = .list }
        save()
        refreshLayout(from: heightBefore)
    }

    // MARK: - Time

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // Wake on the minute, so a reminder rings at its time, not up to a minute late.
                let seconds = Date().timeIntervalSinceReferenceDate
                let untilNextMinute = 60 - seconds.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(untilNextMinute + 0.05))
                guard !Task.isCancelled, let self else { return }
                let before = self.today
                self.now = Date()
                if self.today != before {
                    // A new day: the labels change and something may be due.
                    self.objectWillChange.send()
                }
                self.announceDue()
            }
        }
    }

    /// Shows the strip once for every reminder due today.
    private func announceDue() {
        guard let host else { return }
        let today = today
        var changed = false
        for index in reminders.indices where reminders[index].isRinging(now: now, today: today) && reminders[index].announcedOn != today {
            reminders[index].announcedOn = today
            changed = true
            if showsDueStrip {
                presentDueStrip(for: reminders[index], host: host)
            }
        }
        if changed { save() }
    }

    private func presentDueStrip(for reminder: Reminder, host: DropletHost) {
        let title = reminder.title
        let color = reminder.color
        let request = DropletHUDRequest(
            id: "una-nota.due.\(reminder.id.uuidString)",
            duration: 4.0,
            priority: .normal,
            accessibilityLabel: "Reminder now: \(title)"
        ) {
            HStack(spacing: 0) {
                Image(systemName: "bell.fill")
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                    .foregroundStyle(color)
                Spacer(minLength: 0)
                Text(verbatim: title)
                    .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            }
            .frame(maxWidth: .infinity)
        }
        _ = host.hud.present(request)
    }

    // MARK: - Store

    private func load() {
        guard let host else { return }
        reminders = host.preferences.value(forKey: Keys.reminders, as: [Reminder].self) ?? []
    }

    private func save() {
        guard let host else { return }
        host.preferences.setValue(reminders, forKey: Keys.reminders)
    }

    private func refreshLayout(from previousHeight: CGFloat) {
        guard widgetHeight != previousHeight else { return }
        publishLayoutChange()
    }

    /// Tells the host the widget size changed.
    private func publishLayoutChange() {
        layoutSubject.send(Self.widgetID)
        host?.shelf.invalidateLayout(for: Self.widgetID)
    }

    /// Demo data belongs in the harness and the Playground, never in Droppy itself.
    private static func showsDemoData(in host: DropletHost) -> Bool {
        if host.environment.isHarness { return true }
        return Bundle.main.bundleIdentifier?.localizedCaseInsensitiveContains("playground") == true
    }

    private func seedDemoData() {
        let today = today
        let hour = Calendar.current.component(.hour, from: now)
        reminders = [
            Reminder(title: "Send the invoice", note: "Acme, October. Attach the time sheet and the receipts for the stock photos, and copy the new accountant.", day: today, hour: min(hour + 2, 23), minute: 0, hue: 0.58, tone: 0.5),
            Reminder(title: "Dentist", note: "Bring the insurance card", day: today.adding(days: 1), hour: 11, minute: 30, hue: 0.42, tone: 0.45),
            Reminder(title: "Pick up the parcel", note: "Locker 14 by the pharmacy, the code is in the mail from this morning. It goes back on Friday.", day: today.adding(days: 2), hour: 17, minute: 0, hue: 0.95, tone: 0.3),
            Reminder(title: "Renew the domain", note: "", day: today.adding(days: 12), hour: 10, minute: 0, hue: 0.08, tone: 0.6),
            Reminder(title: "Mum's birthday", note: "Flowers and a call", day: today.adding(days: 40), hour: 9, minute: 0, hue: 0.88, tone: 0.25),
            Reminder(title: "Water the plants", note: "", day: today.adding(days: -2), hour: 8, minute: 0, hue: 0.32, tone: 0.55),
            Reminder(title: "Call the landlord", note: "About the heating", day: today.adding(days: -1), hour: 19, minute: 0, hue: 0.62, tone: 0.7, completedAt: now.addingTimeInterval(-3600))
        ]
        save()
    }
}

// MARK: - Shelf widget

extension UnaNotaDroplet: ShelfWidgetProviding {
    /// Space the host adds above and below the widget.
    static let hostInsets: CGFloat = DroppySpacing.sm * 2
    static let navHeight: CGFloat = 28

    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 8
    /// Between the header row (whose count line hangs under it) and the first row.
    static let listGap: CGFloat = DroppySpacing.xl
    static let listRows = 4
    static let noteFont = NSFont.systemFont(ofSize: 12)
    static let noteMaxLines = 6
    /// Note text width in a row: the widget less the host's insets and the row's paddings.
    static let noteWidth: CGFloat = 380 - hostInsets - (DroppySpacing.md + 8 + DroppySpacing.smd) - DroppySpacing.md

    /// Room the unfolded note adds to its row: its lines, up to `noteMaxLines`, and the padding under.
    static func noteHeight(for note: String) -> CGFloat {
        guard !note.isEmpty else { return 0 }
        let lineHeight = ceil(noteFont.ascender - noteFont.descender + noteFont.leading) + 2
        let bounds = (note as NSString).boundingRect(
            with: CGSize(width: noteWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: noteFont]
        )
        let lines = min(max(Int(ceil(bounds.height / lineHeight)), 1), noteMaxLines)
        return CGFloat(lines) * lineHeight + DroppySpacing.smd
    }

    /// Widget height in a row with other widgets.
    static let groupedHeight: CGFloat = hostInsets + 94

    static let startScreenHeight: CGFloat = 176

    static let detailBodyHeight: CGFloat = 92
    static let flowBodyHeight: CGFloat = WheelStyle.date.height
    static let actionHeight: CGFloat = 28

    var widgetHeight: CGFloat {
        if isInGroupedRow { return Self.groupedHeight }
        let frame = Self.hostInsets
        if pendingDelete != nil {
            return frame + Self.navHeight + DroppySpacing.md + Self.detailBodyHeight + DroppySpacing.md + Self.actionHeight
        }
        switch screen {
        case .list:
            if reminders.isEmpty { return frame + Self.startScreenHeight }
            let items = listed
            let rows = CGFloat(min(max(items.count, 1), Self.listRows))
            let unfolded = expandedID.flatMap { id in items.first { $0.id == id } }.map { Self.noteHeight(for: $0.note) } ?? 0
            return frame + Self.navHeight + Self.listGap + rows * Self.rowHeight + (rows - 1) * Self.rowSpacing + unfolded
        case .detail:
            return frame + Self.navHeight + DroppySpacing.md + Self.detailBodyHeight + DroppySpacing.md + Self.actionHeight
        case .newReminder, .editReminder:
            return frame + Self.navHeight + DroppySpacing.md + Self.flowBodyHeight
        }
    }

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Una Nota",
                systemImage: "bell.badge.fill",
                layoutTraits: layoutTraits,
                focusPolicy: isInFlow ? .keyboardFocusable : .none,
                searchKeywords: ["reminder", "reminders", "note", "todo", "task", "date", "day"]
            )
        ]
    }

    var layoutTraits: ShelfWidgetLayoutTraits {
        ShelfWidgetLayoutTraits(
            preferredSoloWidth: 380,
            preferredPairedWidth: 210,
            contentHeight: .fixed(widgetHeight)
        )
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        if !context.isPreview, host?.environment.isHarness == false {
            let grouped = context.isCompact
            let leavesSoloScreen = grouped && screen != .list
            if grouped != isInGroupedRow || leavesSoloScreen {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if grouped != self.isInGroupedRow {
                        self.isInGroupedRow = grouped
                        self.publishLayoutChange()
                    }
                    if leavesSoloScreen {
                        self.draft = nil
                        self.show(.list)
                    }
                }
            }
        }
        return AnyView(UnaNotaWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }

    /// Shows the widget on its own.
    public func showWidgetAlone() {
        _ = host?.shelf.open(revealing: Self.widgetID)
    }
}

extension UnaNotaDroplet: ShelfWidgetDynamicLayoutProviding {
    /// Current size, read by the host when the shelf opens.
    public func currentLayoutTraits(for id: ShelfWidgetID) -> ShelfWidgetLayoutTraits? {
        id == Self.widgetID ? layoutTraits : nil
    }

    public var shelfWidgetLayoutInvalidationPublisher: AnyPublisher<ShelfWidgetID, Never> {
        layoutSubject.eraseToAnyPublisher()
    }
}

// MARK: - Settings

extension UnaNotaDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(UnaNotaSettings(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Show a strip when a reminder is due", keywords: ["strip", "hud", "due", "notch", "notify"]),
            SettingsSearchEntry(title: "Keep completed reminders", keywords: ["completed", "done", "history", "keep"])
        ]
    }
}
