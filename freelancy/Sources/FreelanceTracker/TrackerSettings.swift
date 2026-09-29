import AppKit
import DroppyKit
import SwiftUI

struct FreelanceTrackerSettings: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    @State private var expandedProjectID: UUID?

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("New projects")
            } content: {
                DropletSettingsCard {
                    DropletSliderRow(
                        title: "Hourly rate",
                        value: droplet.defaultCurrency.formatRate(droplet.defaultRate),
                        binding: droplet.defaultRateBinding,
                        range: 1...500,
                        step: 1
                    )
                    DropletControlRow(
                        title: "Currency",
                        infoTip: "What the rate slider on the shelf starts from. Every project picks its own when it is created."
                    ) {
                        CurrencyPicker(selected: droplet.defaultCurrency, showsName: true) { droplet.setDefaultCurrency($0) }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Shelf")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Start new sessions running",
                        subtitle: "Off, a new session waits on the timer until you press Start, and whatever was running keeps running.",
                        isOn: droplet.startsSessionsRunningBinding
                    )
                    DropletToggleRow(
                        title: "Ask before starting a new session",
                        subtitle: "The plus on the timer asks first. Off, it starts the session at once.",
                        isOn: droplet.asksBeforeNewSessionBinding
                    )
                    DropletToggleRow(
                        title: "Name new sessions",
                        subtitle: "The plus asks for a name before the session starts. Left empty, it gets the next Session number.",
                        isOn: droplet.namesNewSessionsBinding
                    )
                    DropletToggleRow(
                        title: "Ask before switching projects",
                        subtitle: "Picking another project while a session runs asks first. The running session keeps running either way.",
                        isOn: droplet.asksBeforeSwitchingBinding
                    )
                    DropletToggleRow(
                        title: "Show me the money",
                        subtitle: "The amount gets the big digits and the clock the small ones, on the timer and every card. Time is money, but money is money.",
                        isOn: droplet.moneyFirstBinding
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Notch")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Keep the tracker in the notch",
                        subtitle: "While a session runs, the clock and the money stay beside the notch. Off, they show only while the pointer is over it.",
                        isOn: droplet.pinsLiveActivityBinding
                    )
                    DropletToggleRow(
                        title: "Show the amount in the notch",
                        subtitle: "Off, the notch shows the session's time in the project's colour.",
                        isOn: droplet.notchShowsMoneyBinding
                    )
                    DropletToggleRow(
                        title: "Show a strip on start and pause",
                        subtitle: "A brief strip on the notch when a session starts, resumes or pauses.",
                        isOn: droplet.showsHUDBinding
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Projects and sessions")
            } content: {
                DropletSettingsCard {
                    if droplet.projects.isEmpty {
                        DropletControlRow(title: "No projects yet") {
                            DropletValuePill(text: "Add one from the shelf")
                        }
                    } else {
                        ForEach(droplet.projects) { project in
                            ProjectSettingsRow(
                                droplet: droplet,
                                project: project,
                                isExpanded: expandedProjectID == project.id
                            ) {
                                withAnimation(DroppyAnimation.state) {
                                    expandedProjectID = expandedProjectID == project.id ? nil : project.id
                                }
                            }
                            if expandedProjectID == project.id {
                                SessionRows(droplet: droplet, project: project)
                            }
                        }
                    }
                }
                .droppyFlatGlassControls()
            }
        }
        .onAppear {
            if expandedProjectID == nil {
                expandedProjectID = droplet.currentProject?.id
            }
        }
    }
}

private extension View {
    /// On macOS 15 and later the pane is Droppy's grouped Form and the Form pays a row's
    /// padding; before that the rows draw their own, the way the kit's legacy rows do.
    @ViewBuilder
    func settingsRowPadding() -> some View {
        if #available(macOS 15.0, *) {
            self
        } else {
            padding(.horizontal, DroppySettingsLayoutMetrics.rowPadding)
                .padding(.vertical, DroppySettingsLayoutMetrics.rowVerticalPadding)
        }
    }
}

private struct ProjectSettingsRow: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    @State private var draftName: String = ""
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DroppySpacing.sm) {
            ProjectLookMenu(
                project: project,
                setColor: { droplet.setColor(project.id, to: $0) },
                setIcon: { droplet.setIcon(project.id, to: $0) }
            )

            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $draftName, prompt: Text("Name"))
                    .labelsHidden()
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                Text(verbatim: caption)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DroppySpacing.md)

            if confirmingDelete {
                InlineDeleteConfirmation(
                    question: deleteQuestion,
                    cancel: { withAnimation(DroppyAnimation.state) { confirmingDelete = false } },
                    delete: { droplet.deleteProject(project.id) }
                )
                .transition(DroppyTransition.element)
            } else {
                ValueField(
                    display: project.rate == project.rate.rounded() ? String(Int(project.rate)) : String(project.rate),
                    width: 56,
                    help: "The hourly rate"
                ) { text in
                    guard let parsed = Double(text.replacingOccurrences(of: ",", with: ".")), parsed >= 0, parsed.isFinite else { return }
                    droplet.setRate(project.id, to: (parsed * 100).rounded() / 100)
                }

                CurrencyPicker(selected: project.currency, showsName: false) { droplet.setCurrency(project.id, to: $0) }

                Button {
                    withAnimation(DroppyAnimation.state) { confirmingDelete = true }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24, destructive: true, solidFill: nil, foregroundColorOverride: nil))
                .help("Delete this project and its sessions")
                .accessibilityLabel("Delete project")

                Button(action: toggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 24))
                .help(isExpanded ? "Hide sessions" : "Show sessions")
                .accessibilityLabel(isExpanded ? "Hide sessions" : "Show sessions")
            }
        }
        .settingsRowPadding()
        .onAppear { draftName = project.name }
        .onChange(of: project.name) { _, name in
            if !nameFocused { draftName = name }
        }
    }

    private var caption: String {
        let total = droplet.totalSeconds(of: project.id)
        let count = droplet.sessions(of: project.id).count
        var parts = ["\(TrackerClock.brief(total)) · \(project.formattedEarnings(for: total))", "\(count) session\(count == 1 ? "" : "s")"]
        if droplet.sessions(of: project.id).contains(where: { $0.isRunning }) {
            parts.append("running")
        }
        return parts.joined(separator: " · ")
    }

    private var deleteQuestion: String {
        let count = droplet.sessions(of: project.id).count
        return count == 0 ? "Delete this project?" : "Delete with \(count) session\(count == 1 ? "" : "s")?"
    }

    private func commitName() {
        guard draftName != project.name else { return }
        droplet.rename(project.id, to: draftName)
    }
}

private struct InlineDeleteConfirmation: View {
    let question: String
    let cancel: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            Text(verbatim: question)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Cancel", action: cancel)
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
            Button("Delete", action: delete)
                .buttonStyle(DroppyQuietButtonStyle(size: .small, destructive: true))
        }
        .fixedSize()
    }
}

private struct ProjectLookMenu: View {
    let project: Project
    let setColor: @MainActor @Sendable (ProjectColor) -> Void
    let setIcon: @MainActor @Sendable (ProjectIcon) -> Void

    var body: some View {
        Menu {
            Section("Color") {
                Picker("Color", selection: Binding(get: { project.color }, set: setColor)) {
                    ForEach(ProjectColor.allCases) { color in
                        Label {
                            Text(verbatim: color.name)
                        } icon: {
                            Image(nsImage: Self.dot(color.color))
                        }
                        .tag(color)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Icon") {
                Picker("Icon", selection: Binding(get: { project.icon }, set: setIcon)) {
                    ForEach(ProjectIcon.allCases) { icon in
                        Label(icon.name, systemImage: icon.symbol)
                            .tag(icon)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                    .fill(project.color.color.opacity(0.22))
                Image(systemName: project.icon.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(project.color.color)
            }
            .frame(width: 28, height: 28)
            .contentShape(RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Color and icon")
        .accessibilityLabel("Color \(project.color.name), icon \(project.icon.name)")
    }

    private static func dot(_ color: Color) -> NSImage {
        let fill = NSColor(color)
        let image = NSImage(size: NSSize(width: 12, height: 12))
        image.lockFocus()
        fill.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}


/// The expanded project's sessions, one Form row each, indented under the project's name.
private struct SessionRows: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project

    /// The look square and the gap after it, so a session lines up with its project's name.
    static let indent: CGFloat = 28 + DroppySpacing.sm

    var body: some View {
        let sessions = droplet.sessions(of: project.id)
        if sessions.isEmpty {
            Text("No sessions yet. Press Start on the shelf.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.leading, Self.indent)
                .settingsRowPadding()
                .transition(DroppyTransition.element)
        } else {
            ForEach(sessions) { session in
                SessionSettingsRow(droplet: droplet, project: project, session: session)
                    .transition(DroppyTransition.element)
            }
        }
    }
}

private struct SessionSettingsRow: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project
    let session: WorkSession

    @State private var draftName: String = ""
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: DroppySpacing.md) {
            TextField("Name", text: $draftName, prompt: Text("Name"))
                .labelsHidden()
                .textFieldStyle(.plain)
                .foregroundStyle(.primary)
                .focused($nameFocused)
                .onSubmit { commitName() }
                .onChange(of: nameFocused) { _, focused in
                    if !focused { commitName() }
                }
            if !confirmingDelete {
                Text(verbatim: session.isRunning ? "Running" : session.dayLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .transition(DroppyTransition.element)
            }
            Spacer(minLength: DroppySpacing.md)
            if confirmingDelete {
                EmptyView()
            } else if session.isRunning {
                Text(verbatim: TrackerClock.full(session.duration(at: droplet.now)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .transition(DroppyTransition.element)
            } else {
                ValueField(
                    display: TrackerClock.full(session.duration(at: droplet.now)),
                    width: 72,
                    help: "The length, for example 1:30 or 90"
                ) { text in
                    guard let seconds = TrackerClock.parse(text) else { return }
                    droplet.setDuration(of: session.id, seconds: seconds)
                }
                .transition(DroppyTransition.element)
            }
            Text(verbatim: project.formattedEarnings(for: session.duration(at: droplet.now)))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(minWidth: 72, alignment: .trailing)
            if confirmingDelete {
                InlineDeleteConfirmation(
                    question: "Delete?",
                    cancel: { withAnimation(DroppyAnimation.state) { confirmingDelete = false } },
                    delete: { droplet.deleteSession(session.id) }
                )
                .transition(DroppyTransition.element)
            } else {
                Button {
                    withAnimation(DroppyAnimation.state) { confirmingDelete = true }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: true, solidFill: nil, foregroundColorOverride: nil))
                .help("Delete this session")
                .accessibilityLabel("Delete session")
            }
        }
        .padding(.leading, SessionRows.indent)
        .settingsRowPadding()
        .onAppear { draftName = session.name }
        .onChange(of: session.name) { _, name in
            if !nameFocused { draftName = name }
        }
    }

    private func commitName() {
        guard draftName != session.name else { return }
        droplet.renameSession(session.id, to: draftName)
    }
}

/// The currency as the Form's own pop-up.
private struct CurrencyPicker: View {
    let selected: TrackerCurrency
    let showsName: Bool
    let select: @MainActor @Sendable (TrackerCurrency) -> Void

    var body: some View {
        Picker("Currency", selection: Binding(get: { selected }, set: select)) {
            ForEach(TrackerCurrency.all) { currency in
                Text(verbatim: showsName ? "\(currency.code) · \(currency.name)" : currency.code)
                    .tag(currency)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        .help("Currency")
    }
}

/// A native text field for a number: shows the stored value, commits on Return or when it
/// loses focus, and puts the stored value back on Escape or when the typing does not parse.
private struct ValueField: View {
    let display: String
    let width: CGFloat
    let help: String
    let commit: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(help, text: $text)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: width)
            .focused($focused)
            .onSubmit { finish() }
            .onExitCommand {
                text = display
                focused = false
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { finish() }
            }
            .onAppear { text = display }
            .onChange(of: display) { _, value in text = value }
            .help(help)
    }

    private func finish() {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, typed != display {
            commit(typed)
        }
        text = display
    }
}
