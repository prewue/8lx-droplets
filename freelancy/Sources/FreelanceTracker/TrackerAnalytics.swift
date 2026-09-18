import DroppyKit
import SwiftUI

struct DayTotal: Identifiable, Equatable {
    let day: Date
    let seconds: TimeInterval
    let earned: Double

    var id: Date { day }
}

struct ProjectFigures: Equatable {
    let totalSeconds: TimeInterval
    let totalEarned: Double
    let sessionCount: Int
    let averageSeconds: TimeInterval
    let bestDay: DayTotal?
    let lastWorked: Date?

    let recent: [DayTotal]

    static let days = 14
}

extension FreelanceTrackerDroplet {
    func figures(of project: Project) -> ProjectFigures {
        let calendar = Calendar.current
        let sessions = sessions(of: project.id)
        var byDay: [Date: TimeInterval] = [:]
        var total: TimeInterval = 0
        var last: Date?
        for session in sessions {
            let seconds = session.duration(at: now)
            total += seconds
            let day = calendar.startOfDay(for: session.createdAt)
            byDay[day, default: 0] += seconds
            if last == nil || session.createdAt > last! { last = session.createdAt }
        }
        let today = calendar.startOfDay(for: now)
        let recent: [DayTotal] = (0..<ProjectFigures.days).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let seconds = byDay[day] ?? 0
            return DayTotal(day: day, seconds: seconds, earned: project.earnings(for: seconds))
        }
        let best = byDay.max { $0.value < $1.value }.map { DayTotal(day: $0.key, seconds: $0.value, earned: project.earnings(for: $0.value)) }
        return ProjectFigures(
            totalSeconds: total,
            totalEarned: project.earnings(for: total),
            sessionCount: sessions.count,
            averageSeconds: sessions.isEmpty ? 0 : total / Double(sessions.count),
            bestDay: best.flatMap { $0.seconds > 0 ? $0 : nil },
            lastWorked: last,
            recent: recent
        )
    }
}

enum TrackerCSV {
    static let header = "Project,Session,Date,Started,Duration,Hours,Rate,Currency,Earned,Status"

    static func render(projects: [Project], sessions: [WorkSession], now: Date) -> String {
        let byID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let ordered = sessions.sorted { $0.createdAt < $1.createdAt }
        var lines = [header]
        for session in ordered {
            guard let project = byID[session.projectID] else { continue }
            let seconds = session.duration(at: now)
            let started = session.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "en_US_POSIX")))
            let fields = [
                project.name,
                session.name,
                session.createdAt.formatted(.iso8601.year().month().day().dateSeparator(.dash)),
                started,
                TrackerClock.full(seconds),
                String(format: "%.2f", seconds / 3600),
                String(format: "%g", project.rate),
                project.currencyCode,
                String(format: "%.2f", project.earnings(for: seconds)),
                session.isRunning ? "Running" : "Done"
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct AnalyticsScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    @State private var selectedID: UUID?
    @State private var page = 0

    private static let pageCount = 3

    private var project: Project? {
        if let selectedID, let project = droplet.project(selectedID) { return project }
        return droplet.currentProject
    }

    var body: some View {
        VStack(spacing: DroppySpacing.sm) {
            HStack(spacing: DroppySpacing.sm) {
                CornerButton(systemImage: "chevron.left", help: "Back") { droplet.show(.menu) }
                if let project {
                    ProjectTabs(projects: droplet.projects, selectedID: project.id) { selectedID = $0 }
                    CornerButton(systemImage: "arrow.down.doc", help: "Download this project as CSV") { droplet.exportCSV(projectID: project.id) }
                } else {
                    Spacer(minLength: 0)
                    Text("Analytics")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    Spacer(minLength: 0)
                }
            }
            .frame(height: FreelanceTrackerDroplet.navHeight)

            if let project {
                let figures = droplet.figures(of: project)

                PagedScroll(pageCount: Self.pageCount, page: $page) { pageWidth in
                    TotalsPage(project: project, figures: figures)
                        .frame(width: pageWidth)
                    ChartPage(
                        title: "Time · 14 days",
                        total: TrackerClock.brief(figures.recent.reduce(0) { $0 + $1.seconds }),
                        days: figures.recent,
                        value: \.seconds,
                        color: AdaptiveColors.notchSurfacePrimaryText
                    )
                    .frame(width: pageWidth)
                    ChartPage(
                        title: "Money · 14 days",
                        total: project.currency.format(figures.recent.reduce(0) { $0 + $1.earned }, compact: true),
                        days: figures.recent,
                        value: \.earned,
                        color: project.color.color
                    )
                    .frame(width: pageWidth)
                }
                .frame(height: FreelanceTrackerDroplet.analyticsPageHeight)
                .padding(.top, DroppySpacing.lg - DroppySpacing.sm)

                HStack(spacing: DroppySpacing.xsm) {
                    ForEach(0..<Self.pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == page ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceTertiaryText.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: FreelanceTrackerDroplet.pageDotsHeight)
                .padding(.top, DroppySpacing.md - DroppySpacing.sm)
                .animation(DroppyAnimation.state, value: page)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page \(page + 1) of \(Self.pageCount)")
            } else {
                EmptyNote(text: "No projects yet. Add one from Projects.")
            }
        }
        .onAppear { selectedID = droplet.analyticsProjectID ?? droplet.currentProject?.id }
    }
}

private struct ProjectTabs: View {
    let projects: [Project]
    let selectedID: UUID
    let select: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            FadingScroll {
                HStack(spacing: DroppySpacing.xsm) {
                    ForEach(projects) { project in
                        let isSelected = project.id == selectedID
                        Button {
                            withAnimation(DroppyAnimation.segmentedSelection) { select(project.id) }
                        } label: {
                            Text(verbatim: project.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(isSelected ? project.color.color : AdaptiveColors.notchSurfaceSecondaryText)
                                .padding(.horizontal, DroppySpacing.md)
                                .frame(height: FreelanceTrackerDroplet.navHeight)
                        }
                        .buttonStyle(DroppyGlassButtonStyle(fill: isSelected ? .tinted(project.color.color) : .veil))
                        .animation(DroppyAnimation.segmentedSelection, value: isSelected)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .id(project.id)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
        }
    }
}

private struct TotalsPage: View {
    let project: Project
    let figures: ProjectFigures

    var body: some View {
        VStack(spacing: DroppySpacing.xs) {
            AnimatedFigure(
                "\(figures.sessionCount) session\(figures.sessionCount == 1 ? "" : "s")",
                font: .system(size: 12, weight: .medium),
                color: AdaptiveColors.notchSurfaceSecondaryText
            )
            .frame(height: 14)
            AnimatedFigure(
                project.currency.format(figures.totalEarned),
                font: .system(size: 26, weight: .semibold, design: .rounded),
                color: project.color.color
            )
            .frame(height: 30)
            AnimatedFigure(
                TrackerClock.full(figures.totalSeconds),
                font: .system(size: 13, weight: .medium, design: .rounded),
                color: AdaptiveColors.notchSurfacePrimaryText
            )
            .frame(height: 16)
            Spacer(minLength: DroppySpacing.lg)
            HStack(alignment: .top, spacing: 0) {
                Fact(label: "Best day", value: figures.bestDay.map { "\($0.day.formatted(.dateTime.day().month(.abbreviated))) (\(project.currency.format($0.earned, compact: true)))" } ?? "—")
                Fact(label: "Last worked", value: figures.lastWorked.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "—")
                Fact(label: "Rate", value: project.formattedRate)
            }
            .frame(height: 28)
        }
        .padding(.horizontal, DroppySpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Fact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: label)
                .font(.system(size: 10))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            AnimatedFigure(value, font: .system(size: 12, weight: .semibold, design: .rounded), color: AdaptiveColors.notchSurfacePrimaryText)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

private struct AnimatedFigure: View {
    let text: String
    let font: Font
    let color: Color

    init(_ text: String, font: Font, color: Color) {
        self.text = text
        self.font = font
        self.color = color
    }

    var body: some View {
        Text(verbatim: text)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .animation(DroppyAnimation.state, value: text)
    }
}

private struct ChartPage: View {
    private static let sideInset: CGFloat = 28

    let title: String
    let total: String
    let days: [DayTotal]
    let value: KeyPath<DayTotal, Double>
    let color: Color

    var body: some View {
        let values = days.map { $0[keyPath: value] }
        let peak = max(values.max() ?? 0, 0.000_001)
        VStack(spacing: DroppySpacing.xs) {
            HStack {
                Text(verbatim: title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Spacer(minLength: DroppySpacing.sm)
                AnimatedFigure(total, font: .system(size: 12, weight: .semibold, design: .rounded), color: AdaptiveColors.notchSurfacePrimaryText)
            }
            .lineLimit(1)
            .frame(height: 14)

            HStack(alignment: .bottom, spacing: DroppySpacing.xs) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let isToday = index == values.count - 1
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(value > 0 ? color.opacity(isToday ? 1 : 0.7) : AdaptiveColors.notchSurfaceTertiaryText.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .frame(height: value > 0 ? max(4, FreelanceTrackerDroplet.chartBarHeight * value / peak) : 2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 1)
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(AdaptiveColors.notchSurfacePrimaryText.opacity(0.08))
                    .frame(height: 1)
            }
            .animation(DroppyAnimation.state, value: values)

            HStack {
                Text(verbatim: days.first?.day.formatted(.dateTime.day().month(.abbreviated)) ?? "")
                Spacer(minLength: 0)
                Text("Today")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            .frame(height: 10)
        }
        .padding(.horizontal, Self.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(total)")
    }
}

private let pagedScrollSpace = "pagedScroll"

private struct PagedScroll<Content: View>: View {
    let pageCount: Int
    @Binding var page: Int
    @ViewBuilder let content: (CGFloat) -> Content

    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    @State private var fadeLevel: Double = 0

    private static var spacing: CGFloat { DroppySpacing.md }
    private static var fadeWidth: CGFloat { 32 }

    private var pageWidth: CGFloat { max(1, viewportWidth) }

    private var displacement: CGFloat {
        let stride = pageWidth + Self.spacing
        let progress = offset / stride
        return progress - progress.rounded()
    }

    private var isMoving: Bool { abs(displacement) > 0.004 }

    var body: some View {
        let leadingFade = fadeLevel
        let trailingFade = fadeLevel
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Self.spacing) {
                content(pageWidth)
            }
            .scrollTargetLayout()
            .onGeometryChange(for: CGFloat.self) { proxy in
                -proxy.frame(in: .named(pagedScrollSpace)).minX
            } action: { value in
                offset = value
                let index = max(0, min(pageCount - 1, Int((value / (pageWidth + Self.spacing)).rounded())))
                if page != index { page = index }
            }
        }
        .scrollTargetBehavior(.viewAligned)
        .coordinateSpace(name: pagedScrollSpace)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            viewportWidth = width
        }
        .onChange(of: isMoving) { _, moving in
            if moving {
                withAnimation(.easeOut(duration: 0.12)) { fadeLevel = 1 }
            } else {
                withAnimation(.easeInOut(duration: 0.45).delay(0.25)) { fadeLevel = 0 }
            }
        }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(1 - leadingFade), .black],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: Self.fadeWidth)
                Rectangle()
                LinearGradient(
                    colors: [.black, Color.black.opacity(1 - trailingFade)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: Self.fadeWidth)
            }
        )
    }
}
