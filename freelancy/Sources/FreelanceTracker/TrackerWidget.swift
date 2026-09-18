import AppKit
import DroppyKit
import SwiftUI

struct FreelanceTrackerWidget: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let context: ShelfWidgetContext

    var body: some View {
        Group {
            if context.isCompact {
                PairedView(droplet: droplet)
            } else {
                ZStack(alignment: .top) {
                    if let deletion = droplet.pendingDeletion {
                        ConfirmDeleteScreen(droplet: droplet, deletion: deletion)
                            .id(deletion)
                            .transition(DroppyTransition.element)
                    } else {
                        screen
                            .id(droplet.screen)
                            .transition(DroppyTransition.element)
                    }
                }
                .animation(DroppyAnimation.state, value: droplet.screen)
                .animation(DroppyAnimation.state, value: droplet.pendingDeletion)
            }
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var screen: some View {
        Group {
            switch droplet.screen {
            case .menu:
                MenuScreen(droplet: droplet)
            case .timer:
                if let project = droplet.currentProject {
                    TimerScreen(droplet: droplet, project: project)
                } else {
                    NewProjectScreen(droplet: droplet)
                }
            case .projects:
                ProjectsScreen(droplet: droplet)
            case .sessions:
                if let project = droplet.currentProject {
                    SessionsScreen(droplet: droplet, project: project)
                } else {
                    ProjectsScreen(droplet: droplet)
                }
            case .newProject:
                NewProjectScreen(droplet: droplet)
            case .editProject:
                if let project = droplet.editingProject {
                    EditProjectScreen(droplet: droplet, project: project)
                } else {
                    ProjectsScreen(droplet: droplet)
                }
            case .analytics:
                AnalyticsScreen(droplet: droplet)
            }
        }
        .padding(.top, FreelanceTrackerDroplet.screenTop)
        .padding(.bottom, FreelanceTrackerDroplet.screenBottom)
        .padding(.horizontal, FreelanceTrackerDroplet.screenSide)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CornerButton: View {
    let systemImage: String
    let help: String
    var solid = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(DroppyCircleButtonStyle(
            size: FreelanceTrackerDroplet.navHeight,
            destructive: false,
            solidFill: solid ? AdaptiveColors.notchSurfacePrimaryText : nil,
            foregroundColorOverride: nil
        ))
        .help(help)
        .accessibilityLabel(help)
    }
}

struct NavRow<Center: View, Trailing: View>: View {
    let back: (() -> Void)?
    let center: Center
    let trailing: Trailing

    init(back: (() -> Void)?, @ViewBuilder center: () -> Center, @ViewBuilder trailing: () -> Trailing) {
        self.back = back
        self.center = center()
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            HStack {
                if let back {
                    CornerButton(systemImage: "chevron.left", help: "Back", action: back)
                }
                Spacer(minLength: 0)
                trailing
            }
            center
        }
        .frame(height: FreelanceTrackerDroplet.navHeight)
    }
}

struct ProjectBadge: View {
    let project: Project
    var fontSize: CGFloat = 12
    var height: CGFloat = 24
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: project.name)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(project.color.color)
                .padding(.horizontal, DroppySpacing.md)
                .frame(height: height)
        }
        .buttonStyle(DroppyGlassButtonStyle(fill: .tinted(project.color.color)))
        .scaleEffect(isHovering ? 1.08 : 1)
        .animation(DroppyAnimation.hoverScale, value: isHovering)
        .onHover { isHovering = $0 }
        .help("Choose a project")
        .accessibilityLabel("Project \(project.name), choose another")
    }
}

struct SessionBars: View {
    let sessions: [WorkSession]
    let currentID: UUID?
    let now: Date

    static let slots = 5
    private static let barWidth: CGFloat = 3
    private static let barSpacing: CGFloat = 2
    private static let height: CGFloat = 12

    static var width: CGFloat { CGFloat(slots) * barWidth + CGFloat(slots - 1) * barSpacing }

    var body: some View {
        let recent = Array(sessions.prefix(Self.slots).reversed())
        let durations = recent.map { $0.duration(at: now) }
        let longest = max(durations.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: Self.barSpacing) {
            ForEach(0..<(Self.slots - recent.count), id: \.self) { _ in
                Capsule()
                    .fill(AdaptiveColors.notchSurfaceTertiaryText.opacity(0.35))
                    .frame(width: Self.barWidth, height: Self.barWidth)
            }
            ForEach(Array(recent.enumerated()), id: \.element.id) { index, session in
                Capsule()
                    .fill(session.id == currentID ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceTertiaryText)
                    .frame(width: Self.barWidth, height: max(Self.barWidth, Self.height * durations[index] / longest))
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .bottomLeading)
        .animation(DroppyAnimation.state, value: durations)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last \(recent.count) session\(recent.count == 1 ? "" : "s")")
    }
}

private let fadingScrollSpace = "fadingScroll"

private struct ScrollExtent: Equatable {
    var offset: CGFloat
    var width: CGFloat
}

struct FadingScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    private static var fadeWidth: CGFloat { 28 }

    var body: some View {
        let fadesLeading = offset > 1
        let fadesTrailing = contentWidth - viewportWidth - offset > 1
        ScrollView(.horizontal, showsIndicators: false) {
            content()
                .onGeometryChange(for: ScrollExtent.self) { proxy in
                    ScrollExtent(offset: -proxy.frame(in: .named(fadingScrollSpace)).minX, width: proxy.size.width)
                } action: { extent in
                    offset = extent.offset
                    contentWidth = extent.width
                }
        }
        .coordinateSpace(name: fadingScrollSpace)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            viewportWidth = width
        }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fadesLeading ? Self.fadeWidth : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fadesTrailing ? Self.fadeWidth : 0)
            }
        )
        .animation(DroppyAnimation.state, value: fadesLeading)
        .animation(DroppyAnimation.state, value: fadesTrailing)
    }
}

struct ListCard: View {
    let isRunning: Bool

    let headline: String

    let detail: String
    let title: String

    let titleColor: Color?
    let caption: String
    let isCurrent: Bool
    let select: () -> Void
    var analytics: (() -> Void)? = nil
    var edit: (() -> Void)? = nil
    let delete: () -> Void

    @State private var isHovering = false

    private var controlsWidth: CGFloat {
        let count = CGFloat(1 + (edit == nil ? 0 : 1) + (analytics == nil ? 0 : 1))
        return count * 20 + (count - 1) * DroppySpacing.xs
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
                    HStack(spacing: DroppySpacing.xs) {
                        Text(verbatim: title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(titleColor ?? AdaptiveColors.notchSurfacePrimaryText)
                        Spacer(minLength: 0)
                        if isRunning {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                                .opacity(isHovering ? 0 : 1)
                        }
                    }
                    .padding(.trailing, isHovering ? controlsWidth : 0)
                    .frame(height: 16)
                    Text(verbatim: headline)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                        .frame(height: 24)
                    HStack(spacing: DroppySpacing.sm) {
                        Text(verbatim: detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        Spacer(minLength: 0)
                        Text(verbatim: caption)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    }
                    .lineLimit(1)
                    .frame(height: 14)
                }
                .padding(DroppySpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: FreelanceTrackerDroplet.cardHeight)
                .background(
                    RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                        .fill(isHovering ? AdaptiveColors.notchSurfaceCardHoverFill : AdaptiveColors.notchSurfaceCardFill)
                )
                .contentShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: DroppySpacing.xs) {
                if let analytics {
                    Button(action: analytics) {
                        Image(systemName: "chart.bar")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 20))
                    .help("Analytics")
                    .accessibilityLabel("Analytics for \(title)")
                }
                if let edit {
                    Button(action: edit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 20))
                    .help("Edit")
                    .accessibilityLabel("Edit \(title)")
                }
                Button(action: delete) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: true, solidFill: nil, foregroundColorOverride: nil))
                .help("Delete")
                .accessibilityLabel("Delete \(title)")
            }
            .padding(DroppySpacing.xsm)
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        .frame(width: FreelanceTrackerDroplet.cardWidth)
        .onHover { hovering in
            withAnimation(DroppyAnimation.hover) { isHovering = hovering }
        }
        .accessibilityElement(children: .contain)
    }
}

struct CardRow<Item: Identifiable, Card: View>: View {
    let items: [Item]
    let card: (Item) -> Card

    init(items: [Item], @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items
        self.card = card
    }

    var body: some View {
        FadingScroll {
            HStack(spacing: FreelanceTrackerDroplet.cardSpacing) {
                ForEach(items) { item in
                    card(item)
                }
            }
        }
        .frame(height: FreelanceTrackerDroplet.cardHeight)
    }
}

struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12))
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            .frame(maxWidth: .infinity)
            .frame(height: FreelanceTrackerDroplet.cardHeight)
    }
}

private struct ConfirmDeleteScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let deletion: PendingDeletion

    private var title: String {
        switch deletion {
        case .project(let id): return "Delete \u{201C}\(droplet.project(id)?.name ?? "this project")\u{201D}?"
        case .session(let id): return "Delete \u{201C}\(droplet.session(id)?.name ?? "this session")\u{201D}?"
        }
    }

    private var note: String {
        switch deletion {
        case .project(let id):
            let count = droplet.sessions(of: id).count
            let total = droplet.totalSeconds(of: id)
            guard count > 0 else { return "It has no sessions yet." }
            return "\(count) session\(count == 1 ? "" : "s") and \(TrackerClock.brief(total)) go with it."
        case .session(let id):
            guard let session = droplet.session(id) else { return "" }
            let seconds = session.duration(at: droplet.now)
            let money = droplet.project(session.projectID)?.formattedEarnings(for: seconds) ?? ""
            return "\(TrackerClock.brief(seconds)) and \(money) go with it."
        }
    }

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            Spacer(minLength: 0)
            VStack(spacing: DroppySpacing.xs) {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                Text(verbatim: note)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
            .multilineTextAlignment(.center)
            .lineLimit(1)
            HStack(spacing: DroppySpacing.sm) {
                Button {
                    droplet.cancelDeletion()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.lg)
                        .frame(height: FreelanceTrackerDroplet.navHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle())
                .keyboardShortcut(.cancelAction)
                Button {
                    droplet.confirmDeletion()
                } label: {
                    Text("Delete")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.lg)
                        .frame(height: FreelanceTrackerDroplet.navHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle(fill: .tinted(Color.red)))
                .accessibilityLabel(title)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MenuScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        HStack(alignment: .top, spacing: DroppySpacing.xxl) {
            if let running = droplet.runningSession, let project = droplet.project(running.projectID) {
                RunningMenuItem(
                    clock: droplet.moneyFirst
                        ? project.formattedEarnings(for: running.duration(at: droplet.now), compact: true)
                        : TrackerClock.compact(running.duration(at: droplet.now)),
                    color: project.color.color
                ) { droplet.open(project.id) }
            } else {
                MenuItem(systemImage: "timer", title: "Timer") { droplet.openTimer() }
            }
            MenuItem(systemImage: "folder", title: "Projects") { droplet.show(.projects) }
            MenuItem(systemImage: "chart.bar", title: "Analytics") { droplet.show(.analytics) }
            MenuItem(systemImage: "gearshape", title: "Settings") { droplet.openSettings() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct MenuItem: View {
    let systemImage: String
    let title: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: DroppySpacing.xsm) {
            Button(action: action) {
                Image(systemName: systemImage)
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 40))
            .help(title)
            Text(verbatim: title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RunningMenuItem: View {
    let clock: String
    let color: Color
    let action: () -> Void

    var body: some View {
        VStack(spacing: DroppySpacing.xsm) {
            Button(action: action) {
                Image(systemName: "timer")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(DroppyGlassButtonStyle(shape: AnyShape(Circle()), fill: .tinted(color)))
            .help("Timer, running")
            RollingDigits(
                clock,
                font: .system(size: 12, weight: .semibold, design: .rounded),
                color: color
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer, running, \(clock)")
    }
}

private struct TimerScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project

    @State private var isCelebrating = false

    @State private var isPressingPause = false

    var body: some View {
        let session = droplet.currentSession(of: project.id)
        let seconds = session?.duration(at: droplet.now) ?? 0
        let isRunning = session?.isRunning ?? false

        VStack(spacing: DroppySpacing.sm) {
            NavRow(back: { droplet.show(.menu) }) {
                ProjectBadge(project: project, height: FreelanceTrackerDroplet.navHeight) { droplet.show(.projects) }
            } trailing: {
                CornerButton(systemImage: "clock.arrow.circlepath", help: "All sessions") { droplet.show(.sessions) }
            }

            HStack(alignment: .top, spacing: DroppySpacing.xl) {
                Button {
                    bounce($isPressingPause)
                    droplet.togglePause(project.id)
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 40))
                .scaleEffect(isPressingPause ? 1.15 : 1)
                .animation(DroppyAnimation.state, value: isRunning)
                .help(isRunning ? "Pause" : (session == nil ? "Start" : "Resume"))
                .accessibilityLabel(isRunning ? "Pause" : "Start")

                let figures = droplet.ordered(time: TrackerClock.full(seconds), money: project.formattedEarnings(for: seconds))
                VStack(spacing: 2) {
                    RollingDigits(
                        figures.first,
                        font: .system(size: 32, weight: .semibold, design: .rounded),
                        color: AdaptiveColors.notchSurfacePrimaryText
                    )
                    .frame(height: 40)
                    RollingDigits(
                        figures.second,
                        font: .system(size: 14, weight: .medium, design: .rounded),
                        color: AdaptiveColors.notchSurfaceTertiaryText
                    )
                    .frame(height: 16)
                }

                Button {
                    bounce($isCelebrating)
                    droplet.newSession(on: project.id)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(DroppyCircleButtonStyle(
                    size: 40,
                    destructive: false,
                    solidFill: AdaptiveColors.notchSurfacePrimaryText,
                    foregroundColorOverride: nil
                ))
                .scaleEffect(isCelebrating ? 1.15 : 1)
                .help("New session")
                .accessibilityLabel("New session")
            }
            .frame(maxWidth: .infinity)
            .frame(height: FreelanceTrackerDroplet.timerRowHeight)

            HStack(spacing: DroppySpacing.sm) {
                SessionBars(sessions: droplet.sessions(of: project.id), currentID: session?.id, now: droplet.now)
                ZStack(alignment: .leading) {
                    Text(verbatim: session?.name ?? "No session yet")
                        .id(session?.id)
                        .transition(DroppyTransition.element)
                }
                .animation(DroppyAnimation.state, value: session?.id)
                Spacer(minLength: DroppySpacing.md)
                Text(verbatim: project.formattedRate)
                    .monospacedDigit()
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            .frame(height: 16)
        }
    }

    private func bounce(_ flag: Binding<Bool>) {
        withAnimation(DroppyAnimation.bounce) { flag.wrappedValue = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(DroppyAnimation.release) { flag.wrappedValue = false }
        }
    }
}

private struct ProjectsScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        VStack(spacing: DroppySpacing.sm) {
            NavRow(back: { droplet.show(.menu) }) {
                Text("Projects")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            } trailing: {
                CornerButton(systemImage: "plus", help: "New project") { droplet.show(.newProject) }
            }

            if droplet.projects.isEmpty {
                EmptyNote(text: "No projects yet. Press the plus to add one.")
            } else {
                CardRow(items: droplet.projects) { project in
                    let total = droplet.totalSeconds(of: project.id)
                    let figures = droplet.ordered(time: TrackerClock.full(total), money: project.formattedEarnings(for: total, compact: true))
                    ListCard(
                        isRunning: droplet.sessions(of: project.id).contains { $0.isRunning },
                        headline: figures.first,
                        detail: figures.second,
                        title: project.name,
                        titleColor: project.color.color,
                        caption: project.formattedRate,
                        isCurrent: project.id == droplet.currentProject?.id,
                        select: { droplet.open(project.id) },
                        analytics: { droplet.showAnalytics(for: project.id) },
                        edit: { droplet.edit(project.id) },
                        delete: { droplet.askToDelete(.project(project.id)) }
                    )
                }
            }
        }
    }
}

private struct SessionsScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project

    var body: some View {
        let sessions = droplet.sessions(of: project.id)
        VStack(spacing: DroppySpacing.sm) {
            NavRow(back: { droplet.show(.timer) }) {
                Text(verbatim: project.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(project.color.color)
            } trailing: {
                CornerButton(systemImage: "plus", help: "New session") { droplet.newSession(on: project.id) }
            }

            if sessions.isEmpty {
                EmptyNote(text: "No sessions yet. Press the plus to start one.")
            } else {
                CardRow(items: sessions) { session in
                    let seconds = session.duration(at: droplet.now)
                    let figures = droplet.ordered(time: TrackerClock.full(seconds), money: project.formattedEarnings(for: seconds, compact: true))
                    ListCard(
                        isRunning: session.isRunning,
                        headline: figures.first,
                        detail: figures.second,
                        title: session.name,
                        titleColor: nil,
                        caption: session.dayLabel,
                        isCurrent: session.id == droplet.currentSession(of: project.id)?.id,
                        select: { droplet.select(session.id) },
                        delete: { droplet.askToDelete(.session(session.id)) }
                    )
                }
            }
        }
    }
}

private struct ProjectForm: View {
    let title: String
    let titleColor: Color
    let note: String
    let confirm: String
    let back: (() -> Void)?
    let initialRate: Double
    let initialCurrency: TrackerCurrency
    let initialColor: ProjectColor
    let commit: (Double, TrackerCurrency, ProjectColor) -> Void

    @State private var rate: Double = 50
    @State private var currency = TrackerCurrency.usd
    @State private var color = ProjectColor.cyan

    private static let labelWidth: CGFloat = 36

    var body: some View {
        VStack(spacing: DroppySpacing.sm) {
            NavRow(back: back) {
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(titleColor)
            } trailing: {
                EmptyView()
            }

            HStack(spacing: DroppySpacing.md) {
                formLabel("Rate")
                Slider(
                    value: Binding(
                        get: { rate },
                        set: { rate = ($0 / 5).rounded() * 5 }
                    ),
                    in: 5...500
                )
                .controlSize(.small)
                .tint(AdaptiveColors.notchSurfacePrimaryText)
                Text(verbatim: currency.formatRate(rate))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: 84, alignment: .trailing)
            }
            .frame(height: FreelanceTrackerDroplet.formRowHeight)

            HStack(spacing: DroppySpacing.md) {
                formLabel("In")
                CurrencyTabs(selected: $currency)
            }
            .frame(height: FreelanceTrackerDroplet.formRowHeight)

            HStack(spacing: DroppySpacing.md) {
                formLabel("Color")
                ColorSwatches(selected: $color)
                Spacer(minLength: 0)
            }
            .frame(height: FreelanceTrackerDroplet.formRowHeight)

            HStack {
                Text(verbatim: note)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                Spacer(minLength: DroppySpacing.md)
                Button(confirm) {
                    commit(rate, currency, color)
                }
                .buttonStyle(DroppyAccentButtonStyle(size: .small))
            }
            .frame(height: FreelanceTrackerDroplet.formRowHeight)
        }
        .onAppear {
            rate = initialRate
            currency = initialCurrency
            color = initialColor
        }
    }

    private func formLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 12))
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            .frame(width: Self.labelWidth, alignment: .leading)
    }
}

private struct NewProjectScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    private var canGoBack: Bool { !droplet.projects.isEmpty }

    var body: some View {
        ProjectForm(
            title: canGoBack ? "New project" : "Your first project",
            titleColor: AdaptiveColors.notchSurfaceSecondaryText,
            note: "Named Project \(droplet.projects.count + 1). Rename it in Settings.",
            confirm: "Create",
            back: canGoBack ? { droplet.show(.projects) } : nil,
            initialRate: droplet.defaultRate,
            initialCurrency: droplet.defaultCurrency,
            initialColor: ProjectColor.suggested(forProjectNumber: droplet.projects.count + 1)
        ) { rate, currency, color in
            droplet.createProject(rate: rate, currency: currency, color: color)
        }
    }
}

private struct EditProjectScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project

    var body: some View {
        ProjectForm(
            title: project.name,
            titleColor: project.color.color,
            note: "Rename it in Settings.",
            confirm: "Save",
            back: { droplet.show(.projects) },
            initialRate: project.rate,
            initialCurrency: project.currency,
            initialColor: project.color
        ) { rate, currency, color in
            droplet.updateProject(project.id, rate: rate, currency: currency, color: color)
        }
        .id(project.id)
    }
}

private struct CurrencyTabs: View {
    @Binding var selected: TrackerCurrency

    var body: some View {
        ScrollViewReader { proxy in
            FadingScroll {
                HStack(spacing: DroppySpacing.xs) {
                    ForEach(TrackerCurrency.all) { currency in
                        let isSelected = currency == selected
                        Button {
                            withAnimation(DroppyAnimation.segmentedSelection) { selected = currency }
                        } label: {
                            Text(verbatim: currency.code)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? AdaptiveColors.dynamicIslandBackgroundAuto : AdaptiveColors.notchSurfaceSecondaryText)
                                .padding(.horizontal, DroppySpacing.sm)
                                .frame(height: 22)
                                .background(
                                    Capsule().fill(isSelected ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceCardFill)
                                )
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(currency.name)
                        .accessibilityLabel(currency.name)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(currency.code)
                    }
                }
            }
            .onAppear { proxy.scrollTo(selected.code, anchor: .center) }
        }
    }
}

private struct ColorSwatches: View {
    @Binding var selected: ProjectColor

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            ForEach(ProjectColor.allCases) { color in
                let isSelected = color == selected
                Button {
                    withAnimation(DroppyAnimation.segmentedSelection) { selected = color }
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 18, height: 18)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(AdaptiveColors.dynamicIslandBackgroundAuto)
                                    .transition(DroppyTransition.element)
                            }
                        }
                        .scaleEffect(isSelected ? 1.2 : 1)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(color.name)
                .accessibilityLabel(color.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}

private struct PairedView: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if droplet.projects.isEmpty {
                    PairedEmptyView()
                } else if droplet.screen == .projects {
                    PairedProjectsView(droplet: droplet)
                } else if let project = droplet.currentProject {
                    PairedTimerView(droplet: droplet, project: project)
                }
            }
            .id(droplet.screen == .projects)
            .transition(DroppyTransition.element)
        }
        .animation(DroppyAnimation.state, value: droplet.screen == .projects)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, FreelanceTrackerDroplet.screenTop)
        .padding(.bottom, FreelanceTrackerDroplet.screenBottom)
        .padding(.horizontal, FreelanceTrackerDroplet.screenSide)
    }
}

private struct PairedTimerView: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project

    @State private var isPressingPause = false

    var body: some View {
        let session = droplet.currentSession(of: project.id)
        let seconds = session?.duration(at: droplet.now) ?? 0
        let isRunning = session?.isRunning ?? false

        VStack(spacing: 0) {
            ProjectBadge(project: project, fontSize: 11, height: 22) { droplet.show(.projects) }
                .frame(height: 22)

            Spacer(minLength: DroppySpacing.xs)

            HStack(alignment: .top, spacing: DroppySpacing.md) {
                Button {
                    withAnimation(DroppyAnimation.bounce) { isPressingPause = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        withAnimation(DroppyAnimation.release) { isPressingPause = false }
                    }
                    droplet.togglePause(project.id)
                } label: {
                    Image(systemName: isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 28))
                .scaleEffect(isPressingPause ? 1.15 : 1)
                .animation(DroppyAnimation.state, value: isRunning)
                .help(isRunning ? "Pause" : "Start")
                .accessibilityLabel(isRunning ? "Pause" : "Start")

                let figures = droplet.ordered(time: TrackerClock.full(seconds), money: project.formattedEarnings(for: seconds))
                VStack(spacing: 1) {
                    RollingDigits(
                        figures.first,
                        font: .system(size: 22, weight: .semibold, design: .rounded),
                        color: AdaptiveColors.notchSurfacePrimaryText
                    )
                    .frame(height: 28)
                    RollingDigits(
                        figures.second,
                        font: .system(size: 11, weight: .medium, design: .rounded),
                        color: AdaptiveColors.notchSurfaceTertiaryText
                    )
                    .frame(height: 13)
                }

                Button {
                    droplet.newSession(on: project.id)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(DroppyCircleButtonStyle(
                    size: 28,
                    destructive: false,
                    solidFill: AdaptiveColors.notchSurfacePrimaryText,
                    foregroundColorOverride: nil
                ))
                .help("New session")
                .accessibilityLabel("New session")
            }

            Spacer(minLength: DroppySpacing.xs)

            HStack(spacing: DroppySpacing.xsm) {
                SessionBars(sessions: droplet.sessions(of: project.id), currentID: session?.id, now: droplet.now)
                Text(verbatim: session?.name ?? "No session yet")
                Spacer(minLength: DroppySpacing.sm)
                Text(verbatim: project.formattedRate)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            .frame(height: 14)
        }
    }
}

private struct PairedProjectsView: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        VStack(spacing: DroppySpacing.xs) {
            HStack {
                Button {
                    droplet.show(.timer)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Back")
                .accessibilityLabel("Back")
                Spacer(minLength: 0)
                Text("Projects")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Spacer(minLength: 0)
                Color.clear.frame(width: 20, height: 20)
            }
            .frame(height: 20)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(droplet.projects) { project in
                        let isCurrent = project.id == droplet.currentProject?.id
                        Button {
                            droplet.open(project.id)
                        } label: {
                            HStack(spacing: DroppySpacing.xsm) {
                                Circle()
                                    .fill(project.color.color)
                                    .frame(width: 6, height: 6)
                                Text(verbatim: project.name)
                                    .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                                    .foregroundStyle(isCurrent ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                                Spacer(minLength: DroppySpacing.sm)
                                Text(verbatim: TrackerClock.compact(droplet.totalSeconds(of: project.id)))
                                    .font(.system(size: 11, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                            }
                            .lineLimit(1)
                            .padding(.horizontal, DroppySpacing.sm)
                            .frame(height: 22)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                                    .fill(isCurrent ? AdaptiveColors.notchSurfaceCardFill : Color.clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(project.name)")
                    }
                }
            }
        }
    }
}

private struct PairedEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            Text("No projects yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            Text("Open the widget alone to add one.")
                .font(.system(size: 11))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension FreelanceTrackerDroplet {
    func ordered(time: String, money: String) -> (first: String, second: String) {
        moneyFirst ? (money, time) : (time, money)
    }
}
