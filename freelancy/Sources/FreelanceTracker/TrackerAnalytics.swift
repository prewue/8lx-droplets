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
    /// The calendar day in the user's time zone, like "2026-09-30".
    static func day(_ date: Date, in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

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
                day(session.createdAt),
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
                        format: { TrackerClock.brief($0.seconds) },
                        color: AdaptiveColors.notchSurfacePrimaryText,
                        accent: project.color.color
                    )
                    .frame(width: pageWidth)
                    ChartPage(
                        title: "Money · 14 days",
                        total: project.currency.format(figures.recent.reduce(0) { $0 + $1.earned }, compact: true),
                        days: figures.recent,
                        value: \.earned,
                        format: { project.currency.format($0.earned, compact: true) },
                        color: project.color.color,
                        accent: project.color.color
                    )
                    .frame(width: pageWidth)
                }
                .frame(height: FreelanceTrackerDroplet.analyticsPageHeight)
                .padding(.top, DroppySpacing.xl - DroppySpacing.sm)

                HStack(spacing: DroppySpacing.xsm) {
                    ForEach(0..<Self.pageCount, id: \.self) { index in
                        Circle()
                            .fill(index == page ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceTertiaryText.opacity(0.4))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: FreelanceTrackerDroplet.pageDotsHeight)
                .padding(.top, FreelanceTrackerDroplet.pageDotsGap - DroppySpacing.sm)
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
                            HStack(spacing: DroppySpacing.xs) {
                                Image(systemName: project.icon.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(verbatim: project.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
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
    private static let barGap: CGFloat = 6
    private static let dotSize: CGFloat = 4

    let title: String
    let total: String
    let days: [DayTotal]
    let value: KeyPath<DayTotal, Double>
    let format: (DayTotal) -> String
    let color: Color
    let accent: Color

    @State private var hovered: Int?
    @State private var rowWidth: CGFloat = 0
    @Environment(\.analyticsIsPaging) private var isPaging

    private var barWidth: CGFloat {
        let count = CGFloat(max(days.count, 1))
        return max(4, (rowWidth - Self.barGap * (count - 1)) / count)
    }

    var body: some View {
        let values = days.map { $0[keyPath: value] }
        let peak = max(values.max() ?? 0, 0.000_001)
        let focus = hovered.flatMap { days.indices.contains($0) ? days[$0] : nil }

        VStack(spacing: DroppySpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: focus.map { $0.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) } ?? title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(focus == nil ? AdaptiveColors.notchSurfaceTertiaryText : AdaptiveColors.notchSurfaceSecondaryText)
                Spacer(minLength: DroppySpacing.sm)
                AnimatedFigure(
                    focus.map(format) ?? total,
                    font: .system(size: 16, weight: .semibold, design: .rounded),
                    color: AdaptiveColors.notchSurfacePrimaryText
                )
            }
            .lineLimit(1)
            .frame(height: 20)

            HStack(alignment: .bottom, spacing: Self.barGap) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    column(index: index, day: day, value: values[index], peak: peak)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                rowWidth = width
            }
            .contentShape(Rectangle())
            .allowsHitTesting(!isPaging)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard !isPaging, rowWidth > 0, !days.isEmpty else { return }
                    let slot = rowWidth / CGFloat(days.count)
                    let index = min(days.count - 1, max(0, Int(location.x / slot)))
                    if hovered != index { hovered = index }
                case .ended:
                    hovered = nil
                }
            }
            .animation(DroppyAnimation.state, value: values)
            .animation(DroppyAnimation.hover, value: hovered)
            .onChange(of: isPaging) { _, paging in
                if paging, hovered != nil { hovered = nil }
            }
        }
        .padding(.horizontal, Self.sideInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(total)")
    }

    @ViewBuilder
    private func column(index: Int, day: DayTotal, value: Double, peak: Double) -> some View {
        let isToday = index == days.count - 1
        let isFocused = hovered == index
        let dimmed = hovered != nil && !isFocused
        VStack(spacing: 3) {
            if value > 0 {
                let floor = barWidth + 4
                let height = max(floor, FreelanceTrackerDroplet.chartBarHeight * value / peak)
                Capsule(style: .continuous)
                    .fill(color.opacity(dimmed ? 0.3 : (isToday || isFocused ? 1 : 0.7)))
                    .frame(width: barWidth, height: height)
            } else {
                Circle()
                    .fill(AdaptiveColors.notchSurfaceTertiaryText.opacity(dimmed ? 0.15 : 0.3))
                    .frame(width: barWidth, height: barWidth)
            }

            Circle()
                .fill(accent)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .opacity(isToday ? 1 : 0)

            Text(verbatim: day.day.formatted(.dateTime.weekday(.narrow)))
                .font(.system(size: 9, weight: isToday || isFocused ? .bold : .medium))
                .foregroundStyle(isToday || isFocused ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceTertiaryText)
                .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
    }
}

private let pagedScrollSpace = "pagedScroll"

private struct AnalyticsPagingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var analyticsIsPaging: Bool {
        get { self[AnalyticsPagingKey.self] }
        set { self[AnalyticsPagingKey.self] = newValue }
    }
}

private struct PagedScroll<Content: View>: View {
    let pageCount: Int
    @Binding var page: Int
    @ViewBuilder let content: (CGFloat) -> Content

    @State private var viewportWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isPaging = false
    @State private var pagingIdle: Task<Void, Never>?

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
            .environment(\.analyticsIsPaging, isPaging)
            .scrollTargetLayout()
            .onGeometryChange(for: CGFloat.self) { proxy in
                -proxy.frame(in: .named(pagedScrollSpace)).minX
            } action: { value in
                if value != offset { notePaging() }
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
        .onDisappear { pagingIdle?.cancel() }
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

    private func notePaging() {
        if !isPaging { isPaging = true }
        pagingIdle?.cancel()
        pagingIdle = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            isPaging = false
        }
    }
}
