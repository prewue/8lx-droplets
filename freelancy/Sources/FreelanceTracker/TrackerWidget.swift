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
                    if let confirmation = droplet.pendingConfirmation {
                        ConfirmScreen(droplet: droplet, confirmation: confirmation, compact: false)
                            .id(confirmation)
                            .transition(DroppyTransition.element)
                    } else {
                        screen
                            .id(droplet.screen)
                            .transition(DroppyTransition.element)
                    }
                }
                .animation(DroppyAnimation.state, value: droplet.screen)
                .animation(DroppyAnimation.state, value: droplet.pendingConfirmation)
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
                if droplet.projects.isEmpty {
                    StartScreen(droplet: droplet)
                } else {
                    MenuScreen(droplet: droplet)
                }
            case .timer:
                if let project = droplet.currentProject {
                    TimerScreen(droplet: droplet, project: project)
                } else {
                    NoProjectScreen(droplet: droplet)
                }
            case .projects:
                ProjectsScreen(droplet: droplet)
            case .sessions:
                if let project = droplet.currentProject {
                    SessionsScreen(droplet: droplet, project: project)
                } else {
                    ProjectsScreen(droplet: droplet)
                }
            case .newProject, .editProject:
                ProjectFlowScreen(droplet: droplet)
            case .renameSession:
                SessionRenameScreen(droplet: droplet)
            case .analytics:
                AnalyticsScreen(droplet: droplet)
            }
        }
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
            HStack(spacing: DroppySpacing.xs) {
                Image(systemName: project.icon.symbol)
                    .font(.system(size: fontSize - 1, weight: .semibold))
                Text(verbatim: project.name)
                    .font(.system(size: fontSize, weight: .medium))
                    .lineLimit(1)
            }
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
    var titleSymbol: String? = nil
    let caption: String
    let isCurrent: Bool
    let select: () -> Void
    var analytics: (() -> Void)? = nil
    var edit: (() -> Void)? = nil
    let delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DroppySpacing.xs) {
                        if let titleSymbol {
                            Image(systemName: titleSymbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(titleColor ?? AdaptiveColors.notchSurfacePrimaryText)
                        }
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
                    .frame(height: 16)
                    Spacer(minLength: 2)
                    Text(verbatim: headline)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(isCurrent ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                        .frame(height: 24)
                    Spacer(minLength: 2)
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
                .padding(.vertical, DroppySpacing.sm)
                .padding(.horizontal, DroppySpacing.mdl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

/// One row of cards that scrolls sideways and takes the height the screen has left.
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
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
    }
}

struct EmptyNote: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12))
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ConfirmScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let confirmation: PendingConfirmation
    let compact: Bool

    private var title: String {
        switch confirmation {
        case .deleteProject(let id): return "Delete \u{201C}\(droplet.project(id)?.name ?? "this project")\u{201D}?"
        case .deleteSession(let id): return "Delete \u{201C}\(droplet.session(id)?.name ?? "this session")\u{201D}?"
        case .newSession: return droplet.startsSessionsRunning ? "Start a new session?" : "Create a new session?"
        case .switchProject(let id): return "Switch to \u{201C}\(droplet.project(id)?.name ?? "this project")\u{201D}?"
        }
    }

    private var note: String {
        switch confirmation {
        case .deleteProject(let id):
            let count = droplet.sessions(of: id).count
            let total = droplet.totalSeconds(of: id)
            guard count > 0 else { return "It has no sessions yet." }
            return "\(count) session\(count == 1 ? "" : "s") and \(TrackerClock.brief(total)) go with it."
        case .deleteSession(let id):
            guard let session = droplet.session(id) else { return "" }
            let seconds = session.duration(at: droplet.now)
            let money = droplet.project(session.projectID)?.formattedEarnings(for: seconds) ?? ""
            return "\(TrackerClock.brief(seconds)) and \(money) go with it."
        case .newSession(let id):
            if let running = droplet.runningSession {
                let place = running.projectID == id ? "" : " on \(droplet.project(running.projectID)?.name ?? "another project")"
                return droplet.startsSessionsRunning
                    ? "\u{201C}\(running.name)\u{201D}\(place) is running and will be paused."
                    : "\u{201C}\(running.name)\u{201D}\(place) keeps running."
            }
            let count = droplet.sessions(of: id).count
            return "It will be \u{201C}Session \(count + 1)\u{201D} on \(droplet.project(id)?.name ?? "this project")."
        case .switchProject:
            guard let running = droplet.runningSession else { return "" }
            let name = droplet.project(running.projectID)?.name ?? "another project"
            return "\u{201C}\(running.name)\u{201D} on \(name) is running and keeps running."
        }
    }

    private var confirmTitle: String {
        switch confirmation {
        case .deleteProject, .deleteSession: return "Delete"
        case .newSession: return droplet.startsSessionsRunning ? "Start" : "Create"
        case .switchProject: return "Switch"
        }
    }

    private var isDestructive: Bool {
        switch confirmation {
        case .deleteProject, .deleteSession: return true
        case .newSession, .switchProject: return false
        }
    }

    private var accent: Color {
        switch confirmation {
        case .newSession(let id), .switchProject(let id):
            return droplet.project(id)?.color.color ?? .red
        case .deleteProject, .deleteSession:
            return .red
        }
    }

    var body: some View {
        let buttonHeight: CGFloat = compact ? 24 : FreelanceTrackerDroplet.navHeight
        VStack(spacing: compact ? DroppySpacing.sm : DroppySpacing.md) {
            Spacer(minLength: 0)
            VStack(spacing: DroppySpacing.xs) {
                Text(verbatim: title)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                Text(verbatim: note)
                    .font(.system(size: compact ? 10 : 11))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(compact ? 2 : 1)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: DroppySpacing.sm) {
                Button {
                    droplet.cancelConfirmation()
                } label: {
                    Text("Cancel")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .padding(.horizontal, compact ? DroppySpacing.md : DroppySpacing.lg)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle())
                Button {
                    droplet.confirmPending()
                } label: {
                    Text(verbatim: confirmTitle)
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .padding(.horizontal, compact ? DroppySpacing.md : DroppySpacing.lg)
                        .frame(height: buttonHeight)
                }
                .buttonStyle(VividGlassButtonStyle(accent: isDestructive ? nil : accent, destructive: isDestructive))
                .accessibilityLabel(title)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SessionNameLine: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project
    let session: WorkSession?

    var body: some View {
        let isFresh = session != nil && session?.id == droplet.freshSessionID
        ZStack(alignment: .leading) {
            if isFresh, let session {
                HStack(spacing: DroppySpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(verbatim: "\(session.name) \(session.isRunning ? "started" : "created")")
                }
                .foregroundStyle(project.color.color)
                .transition(DroppyTransition.element)
            } else {
                Text(verbatim: session?.name ?? "No session yet")
                    .id(session?.id)
                    .transition(DroppyTransition.element)
            }
        }
        .animation(DroppyAnimation.state, value: session?.id)
        .animation(DroppyAnimation.state, value: isFresh)
    }
}

private struct PairedFace: Hashable {
    let confirmation: PendingConfirmation?
    let showsProjects: Bool
    let showsSessions: Bool

    @MainActor
    init(droplet: FreelanceTrackerDroplet) {
        confirmation = droplet.pendingConfirmation
        showsProjects = droplet.screen == .projects
        showsSessions = droplet.screen == .sessions
    }
}

struct ProjectCard: View {
    let project: Project
    let isRunning: Bool
    let headline: String
    let detailLabel: String
    let detail: String
    let select: () -> Void
    let analytics: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    @State private var isHovering = false

    var body: some View {
        let color = project.color.color
        ZStack(alignment: .topTrailing) {
            Button(action: select) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DroppySpacing.xsm) {
                        Image(systemName: project.icon.symbol)
                            .font(.system(size: 13, weight: .semibold))
                        Text(verbatim: project.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if isRunning {
                            Image(systemName: "play.fill")
                                .font(.system(size: 9, weight: .bold))
                                .opacity(isHovering ? 0 : 1)
                        }
                    }
                    .foregroundStyle(color)
                    .frame(height: 16)

                    Spacer(minLength: 2)

                    Text(verbatim: headline)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .frame(height: 24)

                    Spacer(minLength: 2)

                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: detailLabel)
                                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                            Text(verbatim: detail)
                                .monospacedDigit()
                                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        }
                        Spacer(minLength: DroppySpacing.sm)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Rate")
                                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                            Text(verbatim: project.formattedRate)
                                .monospacedDigit()
                                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                }
                .padding(.vertical, DroppySpacing.sm)
                .padding(.horizontal, DroppySpacing.md)
                .frame(width: FreelanceTrackerDroplet.cardWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .contentShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
            }
            .buttonStyle(TintedCardButtonStyle(color: color))

            HStack(spacing: DroppySpacing.xs) {
                Button(action: analytics) {
                    Image(systemName: "chart.bar")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Analytics")
                .accessibilityLabel("Analytics for \(project.name)")
                Button(action: edit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Edit")
                .accessibilityLabel("Edit \(project.name)")
                Button(action: delete) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: true, solidFill: nil, foregroundColorOverride: nil))
                .help("Delete")
                .accessibilityLabel("Delete \(project.name)")
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

private struct TintedCardButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        TintedCardLabel(configuration: configuration, color: color)
    }
}

private struct TintedCardLabel: View {
    let configuration: ButtonStyleConfiguration
    let color: Color

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .droppyGlassControlChrome(
                shape: AnyShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)),
                fill: .tinted(color),
                isHovering: isHovering,
                isPressed: configuration.isPressed
            )
            .onHover { isHovering = $0 }
    }
}

struct VerticalFadingScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    private static var fadeHeight: CGFloat { 18 }

    var body: some View {
        let fadesTop = offset > 1
        let fadesBottom = contentHeight - viewportHeight - offset > 1
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .onGeometryChange(for: ScrollExtent.self) { proxy in
                    ScrollExtent(offset: -proxy.frame(in: .named(verticalFadingScrollSpace)).minY, width: proxy.size.height)
                } action: { extent in
                    offset = extent.offset
                    contentHeight = extent.width
                }
        }
        .coordinateSpace(name: verticalFadingScrollSpace)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            viewportHeight = height
        }
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadesTop ? Self.fadeHeight : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: fadesBottom ? Self.fadeHeight : 0)
            }
        )
        .animation(DroppyAnimation.state, value: fadesTop)
        .animation(DroppyAnimation.state, value: fadesBottom)
    }
}

private let verticalFadingScrollSpace = "verticalFadingScroll"

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

/// What the shelf shows before the first project, in place of the menu: an emblem, the name, a
/// line on what it does, and one button that starts the project flow.
struct StartScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    private var accent: Color { ProjectColor.suggested(forProjectNumber: 1).color }

    var body: some View {
        VStack(spacing: 0) {
            StartEmblem()
                .frame(width: 96, height: 40)

            Text("Freelancy")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .padding(.top, DroppySpacing.sm)

            Text("Time and money for every client, right in the notch.")
                .font(.system(size: 12))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(1)
                .padding(.top, 2)

            Button {
                droplet.startNewProject()
            } label: {
                Text("Create project")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, DroppySpacing.xl)
                    .frame(height: FreelanceTrackerDroplet.flowActionHeight)
            }
            .buttonStyle(VividGlassButtonStyle(accent: accent))
            .padding(.top, DroppySpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A stopwatch with the nine project colours orbiting it on a tilted ring: the dots pass behind
/// and in front of it, smaller and dimmer at the back, and the stopwatch breathes.
private struct StartEmblem: View {
    private static let colors = ProjectColor.allCases.map(\.color)

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spin = time * 0.7
            ZStack {
                dots(spin: spin, time: time, front: false)
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .scaleEffect(1 + 0.05 * sin(time * 2.2))
                dots(spin: spin, time: time, front: true)
            }
        }
        .accessibilityHidden(true)
    }

    private func dots(spin: Double, time: Double, front: Bool) -> some View {
        ZStack {
            ForEach(Self.colors.indices, id: \.self) { index in
                let angle = spin + Double(index) * 2 * .pi / Double(Self.colors.count)
                let depth = sin(angle)
                if (depth >= 0) == front {
                    Circle()
                        .fill(Self.colors[index])
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.65 + 0.35 * (depth + 1) / 2 + 0.1 * sin(time * 3 + Double(index)))
                        .opacity(0.45 + 0.55 * (depth + 1) / 2)
                        .offset(x: 40 * cos(angle), y: 9 * depth)
                }
            }
        }
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

        VStack(spacing: DroppySpacing.md) {
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
                    droplet.requestNewSession(on: project.id)
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
                SessionNameLine(droplet: droplet, project: project, session: session)
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
                CornerButton(systemImage: "plus", help: "New project") { droplet.startNewProject() }
            }

            if droplet.projects.isEmpty {
                EmptyNote(text: "No projects yet. Press the plus to add one.")
            } else {
                CardRow(items: droplet.projects) { project in
                    let total = droplet.totalSeconds(of: project.id)
                    let money = project.formattedEarnings(for: total, compact: true)
                    let time = TrackerClock.full(total)
                    ProjectCard(
                        project: project,
                        isRunning: droplet.sessions(of: project.id).contains { $0.isRunning },
                        headline: droplet.moneyFirst ? money : time,
                        detailLabel: droplet.moneyFirst ? "Time spent" : "Earned",
                        detail: droplet.moneyFirst ? time : money,
                        select: { droplet.requestOpen(project.id) },
                        analytics: { droplet.showAnalytics(for: project.id) },
                        edit: { droplet.edit(project.id) },
                        delete: { droplet.ask(.deleteProject(project.id)) }
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
                CornerButton(systemImage: "plus", help: "New session") { droplet.requestNewSession(on: project.id) }
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
                        edit: { droplet.startRenamingSession(session.id) },
                        delete: { droplet.ask(.deleteSession(session.id)) }
                    )
                }
            }
        }
    }
}

private struct PairedView: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if let confirmation = droplet.pendingConfirmation {
                    ConfirmScreen(droplet: droplet, confirmation: confirmation, compact: true)
                } else if droplet.projects.isEmpty {
                    PairedEmptyView()
                } else if droplet.screen == .projects {
                    PairedProjectsView(droplet: droplet)
                } else if droplet.screen == .sessions, let project = droplet.currentProject {
                    PairedSessionsView(droplet: droplet, project: project)
                } else if let project = droplet.currentProject {
                    PairedTimerView(droplet: droplet, project: project)
                }
            }
            .id(PairedFace(droplet: droplet))
            .transition(DroppyTransition.element)
        }
        .animation(DroppyAnimation.state, value: PairedFace(droplet: droplet))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    droplet.requestNewSession(on: project.id)
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
                PairedSessionPill(droplet: droplet, project: project, session: session)
                Spacer(minLength: DroppySpacing.xs)
                Text(verbatim: project.formattedRate)
                    .monospacedDigit()
                    .padding(.horizontal, DroppySpacing.sm)
                    .frame(height: PairedSessionPill.height)
                    .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)), fill: .veil)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            .frame(height: PairedSessionPill.height)
        }
    }
}

private struct PairedSessionPill: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project
    let session: WorkSession?

    static let height: CGFloat = 22

    @State private var isHovering = false

    var body: some View {
        Button {
            droplet.show(.sessions)
        } label: {
            HStack(spacing: DroppySpacing.xsm) {
                SessionBars(sessions: droplet.sessions(of: project.id), currentID: session?.id, now: droplet.now)
                SessionNameLine(droplet: droplet, project: project, session: session)
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            .padding(.horizontal, DroppySpacing.sm)
            .frame(height: Self.height)
        }
        .buttonStyle(DroppyGlassButtonStyle())
        .scaleEffect(isHovering ? 1.06 : 1)
        .animation(DroppyAnimation.hoverScale, value: isHovering)
        .onHover { isHovering = $0 }
        .help("Choose a session")
        .accessibilityLabel("Session \(session?.name ?? "none"), choose another")
    }
}

private struct PairedSessionsView: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let project: Project

    var body: some View {
        let current = droplet.currentSession(of: project.id)?.id
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
                Text(verbatim: project.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(project.color.color)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Color.clear.frame(width: 20, height: 20)
            }
            .frame(height: 20)

            let sessions = droplet.sessions(of: project.id)
            if sessions.isEmpty {
                Text("No sessions yet")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VerticalFadingScroll {
                    VStack(spacing: 2) {
                        ForEach(sessions) { session in
                            let isCurrent = session.id == current
                            Button {
                                droplet.select(session.id)
                            } label: {
                                HStack(spacing: DroppySpacing.xsm) {
                                    if session.isRunning {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 7, weight: .bold))
                                            .foregroundStyle(project.color.color)
                                    }
                                    Text(verbatim: session.name)
                                        .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                                        .foregroundStyle(isCurrent ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                                    Spacer(minLength: DroppySpacing.sm)
                                    Text(verbatim: TrackerClock.compact(session.duration(at: droplet.now)))
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
                            .accessibilityLabel("Open \(session.name)")
                        }
                    }
                }
            }
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

            VerticalFadingScroll {
                VStack(spacing: 2) {
                    ForEach(droplet.projects) { project in
                        let isCurrent = project.id == droplet.currentProject?.id
                        Button {
                            droplet.requestOpen(project.id)
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
