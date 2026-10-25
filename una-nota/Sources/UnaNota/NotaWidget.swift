import DroppyKit
import SwiftUI

struct UnaNotaWidget: View {
    @ObservedObject var droplet: UnaNotaDroplet
    let context: ShelfWidgetContext

    var body: some View {
        Group {
            if context.isCompact {
                PairedView(droplet: droplet)
            } else {
                ZStack(alignment: .top) {
                    if let id = droplet.pendingDelete, let reminder = droplet.reminder(id) {
                        ConfirmDeleteScreen(droplet: droplet, reminder: reminder)
                            .id(id)
                            .transition(DroppyTransition.element)
                    } else {
                        screen
                            .id(droplet.screen)
                            .transition(DroppyTransition.element)
                    }
                }
                .animation(DroppyAnimation.state, value: droplet.screen)
                .animation(DroppyAnimation.state, value: droplet.pendingDelete)
            }
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var screen: some View {
        Group {
            switch droplet.screen {
            case .list:
                if droplet.reminders.isEmpty {
                    StartScreen(droplet: droplet)
                } else {
                    ListScreen(droplet: droplet)
                }
            case .detail(let id):
                if let reminder = droplet.reminder(id) {
                    DetailScreen(droplet: droplet, reminder: reminder)
                } else {
                    ListScreen(droplet: droplet)
                }
            case .newReminder, .editReminder:
                ReminderFlowScreen(droplet: droplet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct CornerButton: View {
    let systemImage: String
    let help: String
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(DroppyCircleButtonStyle(
            size: UnaNotaDroplet.navHeight,
            destructive: destructive,
            solidFill: nil,
            foregroundColorOverride: nil
        ))
        .help(help)
        .accessibilityLabel(help)
    }
}

struct NavRow<Leading: View, Center: View, Trailing: View>: View {
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let center: () -> Center
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            center()
            HStack(spacing: DroppySpacing.sm) {
                leading()
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(height: UnaNotaDroplet.navHeight)
    }
}

// MARK: - Start

/// Welcome screen shown before the first reminder.
private struct StartScreen: View {
    @ObservedObject var droplet: UnaNotaDroplet

    var body: some View {
        VStack(spacing: 0) {
            StartEmblem()
                .frame(height: 44)
            Text("Welcome to Una Nota")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .padding(.top, DroppySpacing.smd)
            Text("A day, a title and a color for everything you must not forget. It shows up on the notch when the day comes.")
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 340)
                .padding(.top, DroppySpacing.sm)
            Button {
                droplet.startNewReminder()
            } label: {
                Text("New reminder")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, DroppySpacing.xl)
                    .frame(height: 30)
            }
            .buttonStyle(DroppyGlassButtonStyle())
            .padding(.top, DroppySpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A row of colour chips, one of them a bell, the way a list of reminders will look.
private struct StartEmblem: View {
    private static let hues: [Double] = [0.0, 0.1, 0.42, 0.58, 0.75, 0.9]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.2)) { timeline in
            let beat = Int(timeline.date.timeIntervalSinceReferenceDate / 1.2)
            HStack(spacing: DroppySpacing.sm) {
                ForEach(Self.hues.indices, id: \.self) { index in
                    let lit = beat % Self.hues.count == index
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(NotaColor.color(hue: Self.hues[index]))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .opacity(lit ? 1 : 0)
                        }
                        .scaleEffect(lit ? 1.12 : 1)
                        .animation(DroppyAnimation.stateEmphasis, value: lit)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - List

private struct ListScreen: View {
    @ObservedObject var droplet: UnaNotaDroplet

    var body: some View {
        VStack(spacing: UnaNotaDroplet.listGap) {
            NavRow {
                CornerButton(systemImage: "gearshape", help: "Settings") { droplet.openSettings() }
            } center: {
                VStack(spacing: 1) {
                    Text("Reminders")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Text(verbatim: subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .contentTransition(.numericText())
                }
                .animation(DroppyAnimation.state, value: subtitle)
            } trailing: {
                CornerButton(systemImage: "plus", help: "New reminder") { droplet.startNewReminder() }
            }

            let items = droplet.listed
            if items.isEmpty {
                EmptyNote(text: "All clear. Nothing is waiting.")
                    .frame(height: UnaNotaDroplet.rowHeight)
            } else {
                VerticalFadingScroll {
                    VStack(spacing: UnaNotaDroplet.rowSpacing) {
                        ForEach(items) { reminder in
                            ReminderRow(droplet: droplet, reminder: reminder)
                        }
                    }
                    .animation(DroppyAnimation.listChange, value: items.map(\.id))
                    .animation(DroppyAnimation.state, value: droplet.expandedID)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var subtitle: String {
        let open = droplet.openCount
        let due = droplet.reminders.filter { $0.isDue(today: droplet.today) }.count
        if open == 0 { return "Nothing open" }
        if due > 0 { return "\(due) today, \(open) open" }
        return "\(open) open"
    }
}

/// One reminder in the list: tinted glass on the left running into plain glass on the
/// right, the title, the day and time; a chevron unfolds the note.
private struct ReminderRow: View {
    @ObservedObject var droplet: UnaNotaDroplet
    let reminder: Reminder

    @State private var isHovering = false

    private var today: DayStamp { droplet.today }
    private var isFresh: Bool { droplet.freshID == reminder.id }
    private var isUnfolded: Bool { droplet.expandedID == reminder.id && !reminder.note.isEmpty }
    /// Done, or ticked a beat ago and still in place.
    private var looksDone: Bool { reminder.isDone || droplet.completingID == reminder.id }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .trailing) {
                Button {
                    droplet.open(reminder.id)
                } label: {
                    HStack(spacing: DroppySpacing.smd) {
                        Circle()
                            .fill(reminder.color)
                            .frame(width: 8, height: 8)
                            .opacity(looksDone ? 0.4 : 1)
                        Text(verbatim: isFresh ? "\(reminder.title)  ✓" : reminder.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(looksDone ? AdaptiveColors.notchSurfaceTertiaryText : AdaptiveColors.notchSurfacePrimaryText)
                            .lineLimit(1)
                            .overlay(alignment: .leading) {
                                // The strike draws across the title, rather than appearing.
                                Capsule()
                                    .fill(AdaptiveColors.notchSurfaceSecondaryText)
                                    .frame(height: 1.5)
                                    .frame(maxWidth: looksDone ? .infinity : 0, alignment: .leading)
                                    .offset(y: 0.5)
                            }
                            .animation(DroppyAnimation.state, value: looksDone)
                        Spacer(minLength: DroppySpacing.sm)
                        Text(verbatim: dayLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(dayColor)
                            .lineLimit(1)
                            .opacity(isHovering ? 0 : 1)
                            .padding(.trailing, reminder.note.isEmpty ? 0 : 24)
                    }
                    .padding(.horizontal, DroppySpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: UnaNotaDroplet.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(reminder.title), \(dayLabel)")

                HStack(spacing: DroppySpacing.xs) {
                    HStack(spacing: DroppySpacing.xs) {
                        Button {
                            if reminder.isDone {
                                droplet.toggleDone(reminder.id)
                            } else {
                                droplet.complete(reminder.id)
                            }
                        } label: {
                            Image(systemName: looksDone ? "arrow.uturn.backward" : "checkmark")
                        }
                        .buttonStyle(DroppyCircleButtonStyle(size: 20))
                        .help(reminder.isDone ? "Reopen" : "Done")
                        .accessibilityLabel(reminder.isDone ? "Reopen \(reminder.title)" : "Mark \(reminder.title) done")
                        Button {
                            droplet.askToDelete(reminder.id)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(DroppyCircleButtonStyle(size: 20, destructive: true, solidFill: nil, foregroundColorOverride: nil))
                        .help("Delete")
                        .accessibilityLabel("Delete \(reminder.title)")
                    }
                    .opacity(isHovering ? 1 : 0)
                    .allowsHitTesting(isHovering)

                    if !reminder.note.isEmpty {
                        Button {
                            withAnimation(DroppyAnimation.state) { droplet.toggleNote(reminder.id) }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                                .rotationEffect(.degrees(isUnfolded ? 180 : 0))
                                .frame(width: 20, height: 20)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(isUnfolded ? "Hide the note" : "Show the note")
                        .accessibilityLabel(isUnfolded ? "Hide the note" : "Show the note")
                    }
                }
                .padding(.trailing, DroppySpacing.sm)
            }

            if isUnfolded {
                Text(verbatim: reminder.note)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(UnaNotaDroplet.noteMaxLines)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DroppySpacing.md + 8 + DroppySpacing.smd)
                    .padding(.trailing, DroppySpacing.md)
                    .padding(.bottom, DroppySpacing.smd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: UnaNotaDroplet.noteHeight(for: reminder.note), alignment: .top)
                    .clipped()
                    .transition(DroppyTransition.element)
            }
        }
        .background {
            // The reminder's tint on the left, fading into the plain glass by the middle.
            shape
                .fill(reminder.color.opacity(isHovering ? 0.24 : 0.18))
                .mask(LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black.opacity(0.6), location: 0.3),
                    .init(color: .clear, location: 0.75)
                ], startPoint: .leading, endPoint: .trailing))
                .opacity(looksDone ? 0 : 1)
                .animation(DroppyAnimation.hover, value: isHovering)
                .animation(DroppyAnimation.state, value: looksDone)
        }
        .droppyGlassControlChrome(shape: AnyShape(shape), isHovering: isHovering)
        .opacity(looksDone ? 0.6 : 1)
        .animation(DroppyAnimation.state, value: looksDone)
        .onHover { hovering in
            withAnimation(DroppyAnimation.hover) { isHovering = hovering }
        }
        .accessibilityElement(children: .contain)
    }

    private var dayLabel: String {
        if looksDone { return "Done" }
        let when = "\(NotaDate.label(reminder.day, today: today)) \(reminder.time)"
        if reminder.isOverdue(now: droplet.now, today: today) { return "\(when), overdue" }
        return when
    }

    private var dayColor: Color {
        if looksDone { return AdaptiveColors.notchSurfaceTertiaryText }
        if reminder.isDue(today: today) { return reminder.color }
        return AdaptiveColors.notchSurfaceSecondaryText
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

// MARK: - Detail

private struct DetailScreen: View {
    @ObservedObject var droplet: UnaNotaDroplet
    let reminder: Reminder

    private var today: DayStamp { droplet.today }

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            NavRow {
                CornerButton(systemImage: "chevron.left", help: "Back") { droplet.show(.list) }
            } center: {
                Text(verbatim: "\(NotaDate.distance(reminder.day, today: today)) at \(reminder.time)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(reminder.isDue(today: today) ? reminder.color : AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
            } trailing: {
                CornerButton(systemImage: "pencil", help: "Edit") { droplet.edit(reminder.id) }
            }

            VStack(spacing: DroppySpacing.xsm) {
                Text(verbatim: reminder.title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .strikethrough(reminder.isDone)
                    .foregroundStyle(reminder.color)
                    .lineLimit(1)
                if !reminder.note.isEmpty {
                    Text(verbatim: reminder.note)
                        .font(.system(size: 13))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                Text(verbatim: dateLine)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(1)
            }
            .padding(.horizontal, DroppySpacing.xxl)
            .frame(maxWidth: .infinity)
            .frame(height: UnaNotaDroplet.detailBodyHeight)

            HStack(spacing: DroppySpacing.sm) {
                Button {
                    droplet.toggleDone(reminder.id)
                } label: {
                    Text(reminder.isDone ? "Reopen" : "Done")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.xl)
                        .frame(height: UnaNotaDroplet.actionHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle(fill: reminder.isDone ? .veil : .tinted(reminder.color)))
                Button {
                    droplet.askToDelete(reminder.id)
                } label: {
                    Text("Delete")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.lg)
                        .frame(height: UnaNotaDroplet.actionHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle(fill: .tinted(.red)))
            }
            .frame(height: UnaNotaDroplet.actionHeight)
        }
    }

    private var dateLine: String {
        var line = "\(NotaDate.long(reminder.day)), \(reminder.time)"
        if reminder.isDone, let done = reminder.completedAt {
            line += " · done \(NotaDate.label(DayStamp(done), today: today).lowercased())"
        } else if reminder.isOverdue(now: droplet.now, today: today) {
            line += " · overdue"
        }
        return line
    }
}

// MARK: - Confirm

private struct ConfirmDeleteScreen: View {
    @ObservedObject var droplet: UnaNotaDroplet
    let reminder: Reminder

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            Spacer(minLength: 0)
            VStack(spacing: DroppySpacing.xs) {
                Text(verbatim: "Delete \u{201C}\(reminder.title)\u{201D}?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                Text(verbatim: "\(NotaDate.long(reminder.day)), \(reminder.time)")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(1)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: DroppySpacing.sm) {
                Button {
                    droplet.cancelDelete()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.lg)
                        .frame(height: UnaNotaDroplet.navHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle())
                Button {
                    droplet.confirmDelete()
                } label: {
                    Text("Delete")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.lg)
                        .frame(height: UnaNotaDroplet.navHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle(fill: .tinted(.red)))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Paired

/// The short list for a row shared with other widgets.
private struct PairedView: View {
    @ObservedObject var droplet: UnaNotaDroplet

    var body: some View {
        let items = droplet.listed.filter { !$0.isDone }
        VStack(spacing: DroppySpacing.xsm) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("Reminders")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text(verbatim: items.isEmpty ? "" : String(items.count))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)

            if items.isEmpty {
                EmptyNote(text: droplet.reminders.isEmpty ? "No reminders yet" : "All clear")
            } else {
                VerticalFadingScroll {
                    VStack(spacing: DroppySpacing.xs) {
                        ForEach(items) { reminder in
                            Button {
                                droplet.showWidgetAlone()
                                droplet.open(reminder.id)
                            } label: {
                                HStack(spacing: DroppySpacing.sm) {
                                    Circle()
                                        .fill(reminder.color)
                                        .frame(width: 7, height: 7)
                                    Text(verbatim: reminder.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                                        .lineLimit(1)
                                    Spacer(minLength: DroppySpacing.xs)
                                    Text(verbatim: "\(NotaDate.label(reminder.day, today: droplet.today)) \(reminder.time)")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(reminder.isDue(today: droplet.today) ? reminder.color : AdaptiveColors.notchSurfaceTertiaryText)
                                        .lineLimit(1)
                                }
                                .frame(height: 20)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(reminder.title), \(NotaDate.label(reminder.day, today: droplet.today))")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Scroll

private struct ScrollExtent: Equatable {
    var offset: CGFloat
    var length: CGFloat
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
                    ScrollExtent(offset: -proxy.frame(in: .named(verticalFadingScrollSpace)).minY, length: proxy.size.height)
                } action: { extent in
                    offset = extent.offset
                    contentHeight = extent.length
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
