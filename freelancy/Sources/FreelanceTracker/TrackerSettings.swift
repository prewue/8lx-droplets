import DroppyKit
import SwiftUI

struct FreelanceTrackerSettings: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    @State private var expandedProjectID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.lg) {
            defaults
            shelf
            notch
            projects
        }
        .onAppear {
            if expandedProjectID == nil {
                expandedProjectID = droplet.currentProject?.id
            }
        }
    }

    private var defaults: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            settingsSectionHeader("New projects")
            DropletSettingsCard {
                DropletSliderRow(
                    title: "Hourly rate",
                    value: droplet.defaultCurrency.formatRate(droplet.defaultRate),
                    binding: droplet.defaultRateBinding,
                    range: 1...500,
                    step: 1
                )
                DropletSettingsDivider()
                DropletControlRow(
                    title: "Currency",
                    infoTip: "What the rate slider on the shelf starts from. Every project picks its own when it is created."
                ) {
                    CurrencyMenu(selected: droplet.defaultCurrency, showsName: true) { droplet.setDefaultCurrency($0) }
                }
            }
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            settingsSectionHeader("Shelf")
            DropletSettingsCard {
                DropletToggleRow(
                    title: "Start new sessions running",
                    subtitle: "Off, a new session waits on the timer until you press Start, and whatever was running keeps running.",
                    isOn: droplet.startsSessionsRunningBinding
                )
                DropletSettingsDivider()
                DropletToggleRow(
                    title: "Show me the money",
                    subtitle: "The amount gets the big digits and the clock the small ones, on the timer and every card. Time is money, but money is money.",
                    isOn: droplet.moneyFirstBinding
                )
            }
        }
    }

    private var notch: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            settingsSectionHeader("Notch")
            DropletSettingsCard {
                DropletToggleRow(
                    title: "Keep the tracker in the notch",
                    subtitle: "While a session runs, the clock and the money stay beside the notch. Off, they show only while the pointer is over it.",
                    isOn: droplet.pinsLiveActivityBinding
                )
                DropletSettingsDivider()
                DropletToggleRow(
                    title: "Confirm start and pause",
                    subtitle: "A brief strip on the notch when a session starts, resumes or pauses.",
                    isOn: droplet.showsHUDBinding
                )
            }
        }
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            settingsSectionHeader("Projects and sessions")
            DropletSettingsCard {
                if droplet.projects.isEmpty {
                    DropletControlRow(title: "No projects yet") {
                        Text("Add one from the shelf")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(Array(droplet.projects.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { DropletSettingsDivider() }
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
                            SessionList(droplet: droplet, project: project)
                        }
                    }
                }
            }
            .droppyFlatGlassControls()
        }
    }
}

private struct ProjectSettingsRow: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    @State private var draftName: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: DroppySpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitName() }
                    }
                Text(verbatim: caption)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DroppySpacing.md)

            EditablePill(
                display: project.formattedRate,
                draft: project.rate == project.rate.rounded() ? String(Int(project.rate)) : String(project.rate),
                help: "Click to type the hourly rate"
            ) { text in
                guard let parsed = Double(text.replacingOccurrences(of: ",", with: ".")), parsed >= 0, parsed.isFinite else { return }
                droplet.setRate(project.id, to: (parsed * 100).rounded() / 100)
            }

            CurrencyMenu(selected: project.currency, showsName: false) { droplet.setCurrency(project.id, to: $0) }

            Button(action: toggleExpanded) {
                Image(systemName: isExpanded ? "chevron.up" : "list.bullet")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 24))
            .help(isExpanded ? "Hide sessions" : "Show sessions")
            .accessibilityLabel(isExpanded ? "Hide sessions" : "Show sessions")

            Button {
                droplet.deleteProject(project.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 24, destructive: true, solidFill: nil, foregroundColorOverride: nil))
            .help("Delete this project and its sessions")
            .accessibilityLabel("Delete project")
        }
        .padding(DroppySettingsLayoutMetrics.rowPadding)
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

    private func commitName() {
        guard draftName != project.name else { return }
        droplet.rename(project.id, to: draftName)
    }
}

private struct SessionList: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project

    var body: some View {
        let sessions = droplet.sessions(of: project.id)
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            if sessions.isEmpty {
                Text("No sessions yet. Press Start on the shelf.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DroppySpacing.xs)
            }
            ForEach(sessions) { session in
                SessionSettingsRow(droplet: droplet, project: project, session: session)
            }
        }
        .padding(.horizontal, DroppySettingsLayoutMetrics.rowPadding)
        .padding(.bottom, DroppySettingsLayoutMetrics.rowPadding)
        .transition(DroppyTransition.element)
    }
}

private struct SessionSettingsRow: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project
    let session: WorkSession

    @State private var draftName: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        HStack(spacing: DroppySpacing.md) {
            if session.isRunning {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary)
            }
            TextField("Name", text: $draftName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .focused($nameFocused)
                .onSubmit { commitName() }
                .onChange(of: nameFocused) { _, focused in
                    if !focused { commitName() }
                }
            Text(verbatim: session.dayLabel)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer(minLength: DroppySpacing.md)
            if session.isRunning {
                Text(verbatim: TrackerClock.full(session.duration(at: droplet.now)))
                    .font(.system(size: 12, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                EditablePill(
                    display: TrackerClock.full(session.duration(at: droplet.now)),
                    draft: TrackerClock.full(session.duration(at: droplet.now)),
                    help: "Click to type the length, for example 1:30 or 90"
                ) { text in
                    guard let seconds = TrackerClock.parse(text) else { return }
                    droplet.setDuration(of: session.id, seconds: seconds)
                }
            }
            Text(verbatim: project.formattedEarnings(for: session.duration(at: droplet.now)))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(minWidth: 72, alignment: .trailing)
            Button {
                droplet.deleteSession(session.id)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: true, solidFill: nil, foregroundColorOverride: nil))
            .help("Delete this session")
            .accessibilityLabel("Delete session")
        }
        .padding(.vertical, DroppySpacing.xs)
        .padding(.horizontal, DroppySpacing.smd)
        .background(AdaptiveColors.overlayAuto(0.03))
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous))
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

private struct CurrencyMenu: View {
    let selected: TrackerCurrency
    let showsName: Bool
    let select: (TrackerCurrency) -> Void

    private var ink: Color { DroppyGlassControl.neutralInk() }

    var body: some View {
        Menu {
            ForEach(TrackerCurrency.all) { currency in
                Button {
                    select(currency)
                } label: {
                    if currency == selected {
                        Label("\(currency.code) \(currency.symbol) · \(currency.name)", systemImage: "checkmark")
                    } else {
                        Text(verbatim: "\(currency.code) \(currency.symbol) · \(currency.name)")
                    }
                }
            }
        } label: {
            HStack(spacing: DroppySpacing.xs) {
                Text(verbatim: showsName ? "\(selected.code) · \(selected.name)" : selected.code)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(minHeight: DroppySettingsControlMetrics.compactTrailingControlHeight)
            .droppyGlassControlChrome(
                shape: AnyShape(RoundedRectangle(cornerRadius: DroppyRadius.full, style: .continuous))
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .tint(ink)
        .fixedSize()
        .help("Currency")
        .accessibilityLabel("Currency, \(selected.name)")
    }
}

private struct EditablePill: View {
    let display: String
    let draft: String
    let help: String
    let commit: (String) -> Void

    @State private var isEditing = false
    @State private var text = ""
    @State private var isHovering = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .focused($fieldFocused)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 56)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minHeight: DroppySettingsControlMetrics.compactTrailingControlHeight)
                    .background(Capsule().fill(AdaptiveColors.overlayAuto(0.14)))
                    .onSubmit { finish(apply: true) }
                    .onExitCommand { finish(apply: false) }
                    .onAppear {
                        text = draft
                        DispatchQueue.main.async { fieldFocused = true }
                    }
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused, isEditing { finish(apply: true) }
                    }
            } else {
                Text(verbatim: display)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(minHeight: DroppySettingsControlMetrics.compactTrailingControlHeight)
                    .background(Capsule().fill(AdaptiveColors.overlayAuto(isHovering ? 0.14 : 0.08)))
                    .contentShape(Capsule())
                    .onHover { isHovering = $0 }
                    .onTapGesture { isEditing = true }
                    .help(help)
            }
        }
        .animation(DroppyAnimation.hover, value: isHovering)
    }

    private func finish(apply: Bool) {
        guard isEditing else { return }
        isEditing = false
        fieldFocused = false
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if apply, !typed.isEmpty, typed != draft {
            commit(typed)
        }
    }
}
