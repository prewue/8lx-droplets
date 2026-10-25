import AppKit
import DroppyKit
import SwiftUI

// The create and edit flow: a day and a time on wheels, a title and a note, a colour on the line.

struct ReminderFlowScreen: View {
    @ObservedObject var droplet: UnaNotaDroplet

    var body: some View {
        if let draft = droplet.draft {
            ZStack(alignment: .top) {
                FlowStep(droplet: droplet, draft: draft)
                    .id(draft.step.group)
                    .transition(DroppyTransition.element)
            }
            .animation(DroppyAnimation.state, value: draft.step.group)
        } else {
            EmptyView()
        }
    }
}

private struct FlowStep: View {
    @ObservedObject var droplet: UnaNotaDroplet
    let draft: ReminderDraft

    /// 0 on the day, 1 on the time: the day wheels' fold into the chip.
    @State private var fold: CGFloat
    /// Whether the chip and the time wheels are the ones showing.
    @State private var showsTime: Bool

    init(droplet: UnaNotaDroplet, draft: ReminderDraft) {
        self.droplet = droplet
        self.draft = draft
        let onTime = draft.step == .time
        _fold = State(initialValue: onTime ? 1 : 0)
        _showsTime = State(initialValue: onTime)
    }

    private var current: ReminderDraft { droplet.draft ?? draft }
    private var step: ReminderStep { current.step }
    private var day: DayStamp { current.day }
    private var picksColor: Bool { current.picksColor }

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            FlowNav(title: title, back: { droplet.backInDraft() }, hidesTitle: showsTime) {
                // On the time step the chosen day stands where the title was.
                DayChip(day: day, today: droplet.today) { droplet.backInDraft() }
                    .opacity(showsTime ? 1 : 0)
                    .scaleEffect(showsTime ? 1 : 0.72)
                    .allowsHitTesting(step == .time)
                    .accessibilityHidden(step != .time)
            } trailing: {
                Button {
                    droplet.advanceDraft()
                } label: {
                    // The label swaps on Droppy's element transition; the pill follows its width.
                    ZStack {
                        Text(verbatim: actionTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .id(actionTitle)
                            .transition(DroppyTransition.element)
                    }
                    .padding(.horizontal, DroppySpacing.md)
                    .frame(height: UnaNotaDroplet.navHeight)
                    .animation(DroppyAnimation.state, value: actionTitle)
                }
                .buttonStyle(DroppyGlassButtonStyle(fill: step == .text ? .tinted(current.color) : .veil))
                .help(actionTitle)
            }
            .zIndex(1)

            content
                .frame(maxWidth: .infinity)
                .frame(height: UnaNotaDroplet.flowBodyHeight)
        }
        .onChange(of: step == .time) { _, onTime in
            if onTime {
                withAnimation(DroppyAnimation.stateEmphasis) { fold = 1 }
                withAnimation(DroppyAnimation.state.delay(0.14)) { showsTime = true }
            } else {
                withAnimation(DroppyAnimation.state) { showsTime = false }
                withAnimation(DroppyAnimation.stateEmphasis.delay(0.06)) { fold = 0 }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step.group {
        case .pick:
            PickStep(droplet: droplet, draft: draft, fold: fold, showsTime: showsTime)
        case .text:
            TextStep(droplet: droplet, draft: draft)
        }
    }

    private var title: String {
        switch step {
        case .date: "Pick a day"
        case .time: "Pick a time"
        case .text: picksColor ? "Choose color" : "What is it?"
        }
    }

    private var actionTitle: String {
        switch step {
        case .date, .time: "Continue"
        case .text: picksColor ? "Choose" : (draft.isEditing ? "Save" : "Create")
        }
    }
}

struct FlowNav<Center: View, Trailing: View>: View {
    let title: String
    let back: () -> Void
    /// Fades the title out, for something standing in its place.
    var hidesTitle = false
    @ViewBuilder let center: () -> Center
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            ZStack {
                Text(verbatim: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                    .id(title)
                    .transition(DroppyTransition.element)
            }
            .animation(DroppyAnimation.state, value: title)
            .opacity(hidesTitle ? 0 : 1)
            .blur(radius: hidesTitle ? 4 : 0)
            center()
            HStack(spacing: DroppySpacing.sm) {
                CornerButton(systemImage: "chevron.left", help: "Back", action: back)
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(height: UnaNotaDroplet.navHeight)
    }
}

/// The chosen day as a glass pill with a calendar.
struct DayChip: View {
    let day: DayStamp
    let today: DayStamp
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Text(verbatim: NotaDate.chip(day, today: today))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, DroppySpacing.md)
            .frame(height: UnaNotaDroplet.navHeight)
        }
        .buttonStyle(DroppyGlassButtonStyle())
        .help("Change the day")
        .accessibilityLabel("Day, \(NotaDate.long(day)). Change")
    }
}

/// The chosen time as a glass pill with a clock.
struct TimeChip: View {
    let hour: Int
    let minute: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Text(verbatim: NotaDate.time(hour: hour, minute: minute))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, DroppySpacing.md)
            .frame(height: UnaNotaDroplet.navHeight)
        }
        .buttonStyle(DroppyGlassButtonStyle())
        .help("Change the time")
        .accessibilityLabel("Time, \(NotaDate.time(hour: hour, minute: minute)). Change")
    }
}

// MARK: - Day and time

/// The day on three wheels; then the day folds up into the chip in the nav row and the time
/// unfolds in its place.
private struct PickStep: View {
    @ObservedObject var droplet: UnaNotaDroplet
    let draft: ReminderDraft
    let fold: CGFloat
    let showsTime: Bool

    @StateObject private var dayWheel = WheelEngine()
    @StateObject private var monthWheel = WheelEngine()
    @StateObject private var yearWheel = WheelEngine()
    @StateObject private var hourWheel = WheelEngine()
    @StateObject private var minuteWheel = WheelEngine()
    /// The column the arrow keys move.
    @State private var column = 0

    private static let font = Font.system(size: 21, weight: .semibold)
    private static let columnSpacing: CGFloat = 24

    private var current: ReminderDraft { droplet.draft ?? draft }
    private var day: DayStamp { current.day }
    private var isTime: Bool { current.step == .time }
    private var years: [Int] { Array((droplet.today.year - 1)...(droplet.today.year + 29)) }
    private var days: [Int] { Array(1...DayStamp.daysIn(month: day.month, year: day.year)) }

    var body: some View {
        let bodyHeight = UnaNotaDroplet.flowBodyHeight
        // The centre row travels to the middle of the nav row above the body.
        let lift = bodyHeight / 2 + DroppySpacing.md + UnaNotaDroplet.navHeight / 2
        ZStack {
            dateWheels
                .scaleEffect(1 - 0.5 * fold)
                .offset(y: -lift * fold)
                .opacity(showsTime ? 0 : 1)
                .allowsHitTesting(!isTime)
                .accessibilityHidden(isTime)

            timeWheels
                .opacity(showsTime ? 1 : 0)
                .offset(y: showsTime ? 0 : 44)
                .blur(radius: showsTime ? 0 : 10)
                .allowsHitTesting(isTime)
                .accessibilityHidden(!isTime)
        }
        .frame(maxWidth: .infinity)
        .frame(height: bodyHeight)
        .onChange(of: isTime) { _, _ in column = 0 }
        .background {
            FlowKeyReceiver { key, shift in
                switch key {
                case .left: column = max(0, column - 1)
                case .right: column = min(isTime ? 1 : 2, column + 1)
                case .up: wheel(column).step(shift ? -5 : -1)
                case .down: wheel(column).step(shift ? 5 : 1)
                case .enter: droplet.advanceDraft()
                case .escape: droplet.backInDraft()
                }
            }
        }
    }

    private var dateWheels: some View {
        HStack(spacing: Self.columnSpacing) {
            VerticalWheel(
                engine: dayWheel,
                items: days,
                selection: Binding(
                    get: { day.day },
                    set: { chosen in droplet.updateDraft { $0.day.day = chosen } }
                ),
                style: .date,
                collapse: fold
            ) { value, _ in
                Text(verbatim: String(format: "%02d", value))
                    .font(Self.font)
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: 56, height: WheelStyle.date.pitch)
                    .accessibilityLabel("Day \(value)")
            }
            .frame(width: 56)
            .accessibilityLabel("Day")

            VerticalWheel(
                engine: monthWheel,
                items: Array(1...12),
                selection: Binding(
                    get: { day.month },
                    set: { chosen in droplet.updateDraft { $0.day = DayStamp(year: $0.day.year, month: chosen, day: $0.day.day).clamped } }
                ),
                style: .date,
                collapse: fold
            ) { value, _ in
                Text(verbatim: NotaDate.monthName(value))
                    .font(Self.font)
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: 80, height: WheelStyle.date.pitch)
                    .accessibilityLabel(NotaDate.monthName(value))
            }
            .frame(width: 80)
            .accessibilityLabel("Month")

            VerticalWheel(
                engine: yearWheel,
                items: years,
                selection: Binding(
                    get: { day.year },
                    set: { chosen in droplet.updateDraft { $0.day = DayStamp(year: chosen, month: $0.day.month, day: $0.day.day).clamped } }
                ),
                style: .date,
                wraps: false,
                collapse: fold
            ) { value, _ in
                Text(verbatim: String(value))
                    .font(Self.font)
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: 80, height: WheelStyle.date.pitch)
                    .accessibilityLabel("Year \(value)")
            }
            .frame(width: 80)
            .accessibilityLabel("Year")
        }
        .frame(maxWidth: .infinity)
    }

    private var timeWheels: some View {
        HStack(spacing: DroppySpacing.md) {
            VerticalWheel(
                engine: hourWheel,
                items: Array(0...23),
                selection: Binding(
                    get: { current.hour },
                    set: { chosen in droplet.updateDraft { $0.hour = chosen } }
                ),
                style: .time
            ) { value, _ in
                Text(verbatim: String(format: "%02d", value))
                    .font(Self.font)
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: 64, height: WheelStyle.time.pitch)
                    .accessibilityLabel("\(value) hours")
            }
            .frame(width: 64)
            .accessibilityLabel("Hour")

            Text(verbatim: ":")
                .font(Self.font)
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .offset(y: -2)
                .accessibilityHidden(true)

            VerticalWheel(
                engine: minuteWheel,
                items: Array(0...59),
                selection: Binding(
                    get: { current.minute },
                    set: { chosen in droplet.updateDraft { $0.minute = chosen } }
                ),
                style: .time
            ) { value, _ in
                Text(verbatim: String(format: "%02d", value))
                    .font(Self.font)
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: 64, height: WheelStyle.time.pitch)
                    .accessibilityLabel("\(value) minutes")
            }
            .frame(width: 64)
            .accessibilityLabel("Minute")
        }
        .frame(maxWidth: .infinity)
    }

    private func wheel(_ column: Int) -> WheelEngine {
        if isTime {
            return column == 0 ? hourWheel : minuteWheel
        }
        switch column {
        case 0: return dayWheel
        case 1: return monthWheel
        default: return yearWheel
        }
    }
}

// MARK: - Text

/// One glass block: the title, the note filling the rest, the day and time pills over its
/// bottom leading corner and the colour disc over the trailing one. The disc grows into the
/// spectrum across the whole block, and shrinks back into it when the colour is chosen.
private struct TextStep: View {
    @ObservedObject var droplet: UnaNotaDroplet
    let draft: ReminderDraft

    @State private var editsNote = false
    /// 0 with the fields showing, 1 with the spectrum open: the disc's growth.
    @State private var reveal: CGFloat

    private static let titleLength = 60
    private static let noteLength = 300
    private static let inset: CGFloat = DroppySpacing.lg
    private static let discSize: CGFloat = UnaNotaDroplet.navHeight
    /// How soft the edge of the growing circle is.
    private static let morphFeather: CGFloat = 64
    /// The glow under the block: a wide ellipse, most of it past the bottom edge, with a white
    /// core.
    private static let glowWidth: CGFloat = 340
    private static let glowHeight: CGFloat = 200
    private static let coreWidth: CGFloat = 160
    private static let coreHeight: CGFloat = 96

    init(droplet: UnaNotaDroplet, draft: ReminderDraft) {
        self.droplet = droplet
        self.draft = draft
        _reveal = State(initialValue: draft.picksColor ? 1 : 0)
    }

    private var current: ReminderDraft { droplet.draft ?? draft }
    private var picksColor: Bool { current.picksColor }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DroppyRadius.lx, style: .continuous)
        GeometryReader { proxy in
            let size = proxy.size
            let discCentre = CGPoint(
                x: size.width - Self.inset - Self.discSize / 2,
                y: size.height - Self.inset - Self.discSize / 2
            )
            let diameter = Self.discSize + (2 * hypot(size.width, size.height) - Self.discSize) * reveal
            let anchor = UnitPoint(x: discCentre.x / max(size.width, 1), y: discCentre.y / max(size.height, 1))
            ZStack {
                // The block stays as it is; the spectrum blooms over it.
                fields(shape: shape)
                    .opacity(reveal >= 1 ? 0 : 1)
                    .allowsHitTesting(!picksColor)
                    .accessibilityHidden(picksColor)

                SpectrumField(
                    hue: Binding(get: { current.hue }, set: { value in droplet.updateDraft { $0.hue = value } }),
                    tone: Binding(get: { current.tone }, set: { value in droplet.updateDraft { $0.tone = value } }),
                    shape: shape,
                    cover: current.color,
                    reveal: reveal
                )
                // The spectrum swells out of the disc under a soft-edged circle: the morphing
                // shape itself is blurred, so it blooms rather than wipes.
                .scaleEffect(0.9 + 0.1 * reveal, anchor: anchor)
                .saturation(0.6 + 0.4 * Double(reveal))
                .mask {
                    Circle()
                        .frame(width: diameter, height: diameter)
                        .blur(radius: Self.morphFeather)
                        .position(discCentre)
                }
                .allowsHitTesting(picksColor)
                .accessibilityHidden(!picksColor)
                .background {
                    if picksColor {
                        FlowKeyReceiver { key, shift in
                            switch key {
                            case .left: nudgeHue(shift ? -1 / 12 : -1 / 48)
                            case .right: nudgeHue(shift ? 1 / 12 : 1 / 48)
                            case .up: nudgeTone(shift ? -0.1 : -0.02)
                            case .down: nudgeTone(shift ? 0.1 : 0.02)
                            case .enter: droplet.advanceDraft()
                            case .escape: droplet.backInDraft()
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: picksColor) { _, open in
            // Droppy's emphasis curve, slowed so the swell can be watched.
            withAnimation(DroppyAnimation.stateEmphasis.speed(0.55)) { reveal = open ? 1 : 0 }
        }
    }

    private func fields(shape: RoundedRectangle) -> some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            FlowTextField(
                text: Binding(
                    get: { droplet.draft?.title ?? "" },
                    set: { text in droplet.updateDraft { $0.title = String(text.prefix(Self.titleLength)) } }
                ),
                placeholder: "Title",
                font: .systemFont(ofSize: 26, weight: .semibold),
                onSubmit: { editsNote = true },
                onCancel: { droplet.backInDraft() },
                alignment: .left,
                wantsFocus: !editsNote && !picksColor
            )
            .frame(height: 34)
            .onTapGesture { editsNote = false }
            .accessibilityLabel("Title")

            // The note takes everything under the title; the pills float over its foot.
            FlowTextArea(
                text: Binding(
                    get: { droplet.draft?.note ?? "" },
                    set: { text in droplet.updateDraft { $0.note = String(text.prefix(Self.noteLength)) } }
                ),
                placeholder: "Add a note",
                font: .systemFont(ofSize: 13, weight: .regular),
                textColor: AdaptiveColors.notchSurfaceSecondaryText,
                onSubmit: { droplet.advanceDraft() },
                onCancel: { editsNote = false },
                wantsFocus: editsNote && !picksColor
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onTapGesture { editsNote = true }
            .accessibilityLabel("Note")
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, DroppySpacing.md)
        .padding(.bottom, Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: DroppySpacing.sm) {
                DayChip(day: current.day, today: droplet.today) { droplet.revisit(.date) }
                TimeChip(hour: current.hour, minute: current.minute) { droplet.revisit(.time) }
            }
            .padding(.leading, Self.inset)
            .padding(.bottom, Self.inset)
        }
        .overlay(alignment: .bottomTrailing) {
            ColorDisc(color: current.color) { droplet.startPickingColor() }
                .padding(.trailing, Self.inset)
                .padding(.bottom, Self.inset)
        }
        .background(alignment: .bottom) {
            // The colour glows up from under the bottom edge, with a white core.
            ZStack {
                Ellipse()
                    .fill(current.color)
                    .frame(width: Self.glowWidth, height: Self.glowHeight)
                    .blur(radius: 48)
                    .opacity(0.6)
                Ellipse()
                    .fill(.white)
                    .frame(width: Self.coreWidth, height: Self.coreHeight)
                    .blur(radius: 26)
                    .opacity(0.55)
            }
            .offset(y: Self.glowHeight * 0.68)
            .animation(DroppyAnimation.state, value: current.color)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .droppyGlassControlChrome(shape: AnyShape(shape))
    }

    private func nudgeHue(_ delta: Double) {
        let next = ((current.hue + delta).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
        withAnimation(DroppyAnimation.state) { droplet.updateDraft { $0.hue = next } }
    }

    private func nudgeTone(_ delta: Double) {
        let next = min(max(current.tone + delta, 0), 1)
        withAnimation(DroppyAnimation.state) { droplet.updateDraft { $0.tone = next } }
    }
}

/// The chosen colour: a plain disc in it, which the spectrum grows out of.
private struct ColorDisc: View {
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: UnaNotaDroplet.navHeight, height: UnaNotaDroplet.navHeight)
                .scaleEffect(isHovering ? 1.08 : 1)
                .animation(DroppyAnimation.hover, value: isHovering)
                .animation(DroppyAnimation.state, value: color)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Change the color")
        .accessibilityLabel("Color. Change")
    }
}

/// The whole spectrum: the hue across, pastel to dark down, and a disc of clear glass to drag.
private struct SpectrumField: View {
    @Binding var hue: Double
    @Binding var tone: Double
    let shape: RoundedRectangle
    /// The chosen colour, laid over the spectrum while it is still the size of the disc.
    let cover: Color
    /// 0 closed, 1 open.
    let reveal: CGFloat

    static let thumbSize: CGFloat = 28

    @State private var isPressed = false
    @State private var isHovering = false
    @State private var lastTick: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width - Self.thumbSize, 1)
            let height = max(proxy.size.height - Self.thumbSize, 1)
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: NotaColor.spectrum, startPoint: .leading, endPoint: .trailing)
                LinearGradient(stops: [
                    .init(color: .white.opacity(0.7), location: 0),
                    .init(color: .white.opacity(0), location: 0.5),
                    .init(color: .black.opacity(0), location: 0.5),
                    .init(color: .black.opacity(0.62), location: 1)
                ], startPoint: .top, endPoint: .bottom)

                Rectangle()
                    .fill(cover)
                    .opacity(1 - reveal)
                    .allowsHitTesting(false)

                Color.clear
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .droppyGlassControlChrome(shape: AnyShape(Circle()), fill: .veil)
                    .opacity(max(0, (reveal - 0.5) * 2))
                    .blur(radius: 12 * (1 - reveal))
                    .scaleEffect(0.3 + 0.7 * reveal)
                    .scaleEffect(isPressed ? 1.22 : (isHovering ? 1.08 : 1))
                    .shadow(color: .black.opacity(isPressed ? 0.28 : 0.14), radius: isPressed ? 8 : 3, y: isPressed ? 4 : 1)
                    .animation(isPressed ? DroppyAnimation.press : DroppyAnimation.release, value: isPressed)
                    .animation(DroppyAnimation.hover, value: isHovering)
                    .offset(x: width * hue, y: height * tone)
                    .onHover { isHovering = $0 }
            }
            .clipShape(shape)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = true
                        let x = (value.location.x - Self.thumbSize / 2) / width
                        let y = (value.location.y - Self.thumbSize / 2) / height
                        pick(hue: min(max(x, 0), 1), tone: min(max(y, 0), 1))
                    }
                    .onEnded { _ in
                        isPressed = false
                        lastTick = nil
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Color, \(NotaColor.name(hue: hue))")
    }

    private func pick(hue newHue: Double, tone newTone: Double) {
        let tick = Int(newHue * 24) * 8 + Int(newTone * 8)
        if let lastTick, lastTick != tick {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        lastTick = tick
        hue = newHue
        tone = newTone
    }
}

// MARK: - Keyboard

@MainActor
enum FlowFocus {
    static let retryDelays: [Double] = [0, 0.15, 0.4, 0.8, 1.5]

    static func schedule(_ attempt: @escaping @MainActor () -> Void) {
        for delay in retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { attempt() }
            }
        }
    }

    /// Asks the host for keyboard focus. Set while the droplet is active.
    static var requestKey: (@MainActor () -> Bool)?

    static func ensureKey(_ window: NSWindow) -> Bool {
        if window.isKeyWindow { return true }
        _ = requestKey?()
        return window.isKeyWindow
    }
}

enum FlowKey {
    case left, right, up, down, enter, escape
}

struct FlowKeyReceiver: NSViewRepresentable {
    let handler: (FlowKey, Bool) -> Void

    func makeNSView(context: Context) -> FlowKeyView {
        let view = FlowKeyView()
        view.handler = handler
        return view
    }

    func updateNSView(_ view: FlowKeyView, context: Context) {
        view.handler = handler
    }

    static func dismantleNSView(_ view: FlowKeyView, coordinator: ()) {
        view.stopWatching()
    }
}

/// Handles arrows, Return and Escape on steps without a text field.
///
/// Uses a key monitor instead of first responder, since clicks on the step steal first
/// responder. Only the newest receiver responds while two steps overlap.
final class FlowKeyView: NSView {
    var handler: ((FlowKey, Bool) -> Void)?
    private var keyObserver: NSObjectProtocol?
    private var keyMonitor: Any?

    private static weak var newest: FlowKeyView?

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatching()
        guard let window else { return }
        Self.newest = self
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.claimFocus() }
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
        FlowFocus.schedule { [weak self] in self?.claimFocus() }
    }

    func stopWatching() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if Self.newest === self { Self.newest = nil }
    }

    private func claimFocus() {
        guard let window, window.firstResponder !== self else { return }
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return }
        guard FlowFocus.ensureKey(window) else { return }
        window.makeFirstResponder(self)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard Self.newest === self, let window, event.window === window, let handler else { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return false }
        let key: FlowKey
        switch event.keyCode {
        case 123: key = .left
        case 124: key = .right
        case 126: key = .up
        case 125: key = .down
        case 36, 76: key = .enter
        case 53: key = .escape
        default: return false
        }
        handler(key, event.modifierFlags.contains(.shift))
        return true
    }
}

struct FlowTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    var textColor: Color = AdaptiveColors.notchSurfacePrimaryText
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var onEndEditing: (() -> Void)? = nil
    var alignment: NSTextAlignment = .center
    /// Whether this field takes the keyboard. One field on a step says true.
    var wantsFocus = true
    /// Wraps onto more lines; Return still submits.
    var multiline = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FlowNSTextField {
        let field = FlowNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = alignment
        field.font = font
        field.textColor = NSColor(textColor)
        if multiline {
            field.lineBreakMode = .byWordWrapping
            field.usesSingleLineMode = false
            field.maximumNumberOfLines = 4
            field.cell?.isScrollable = false
            field.cell?.wraps = true
        } else {
            field.lineBreakMode = .byTruncatingTail
            field.usesSingleLineMode = true
            field.cell?.isScrollable = true
            field.cell?.wraps = false
        }
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderAttributedString = placeholderString
        field.wantsFocus = wantsFocus
        return field
    }

    func updateNSView(_ field: FlowNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, field.currentEditor() == nil || text.isEmpty {
            field.stringValue = text
        }
        field.placeholderAttributedString = placeholderString
        let wanted = wantsFocus
        if field.wantsFocus != wanted {
            field.wantsFocus = wanted
            if wanted {
                FlowFocus.schedule { [weak field] in field?.claimFocus() }
            } else if field.currentEditor() != nil {
                field.window?.makeFirstResponder(nil)
            }
        }
    }

    static func dismantleNSView(_ field: FlowNSTextField, coordinator: Coordinator) {
        field.stopWatching()
    }

    private var placeholderString: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        return NSAttributedString(string: placeholder, attributes: [
            .font: font,
            .foregroundColor: NSColor(AdaptiveColors.notchSurfaceTertiaryText),
            .paragraphStyle: paragraph
        ])
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FlowTextField

        init(_ parent: FlowTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEndEditing?()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

final class FlowNSTextField: NSTextField {
    var wantsFocus = true
    private var keyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatching()
        guard let window else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.claimFocus() }
        }
        FlowFocus.schedule { [weak self] in self?.claimFocus() }
    }

    func stopWatching() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
    }

    func claimFocus() {
        guard wantsFocus, let window, currentEditor() == nil else { return }
        guard FlowFocus.ensureKey(window) else { return }
        if window.makeFirstResponder(self), let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = NSColor(AdaptiveColors.notchSurfacePrimaryText)
            editor.selectedRange = NSRange(location: stringValue.utf16.count, length: 0)
        }
    }
}

/// A wrapping text field on an `NSTextView`: the text starts at the top and grows down, the
/// way a note does. Return submits, Escape cancels, and it claims the keyboard like the field.
struct FlowTextArea: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let font: NSFont
    var textColor: Color = AdaptiveColors.notchSurfacePrimaryText
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var wantsFocus = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let area = FlowNSTextView()
        area.delegate = context.coordinator
        area.isRichText = false
        area.allowsUndo = true
        area.drawsBackground = false
        area.font = font
        area.textColor = NSColor(textColor)
        area.insertionPointColor = NSColor(AdaptiveColors.notchSurfacePrimaryText)
        area.textContainerInset = .zero
        area.textContainer?.lineFragmentPadding = 0
        area.textContainer?.widthTracksTextView = true
        area.isVerticallyResizable = true
        area.isHorizontallyResizable = false
        area.autoresizingMask = [.width]
        area.string = text
        area.placeholder = placeholder
        area.placeholderColor = NSColor(AdaptiveColors.notchSurfaceTertiaryText)
        area.wantsFocus = wantsFocus
        scroll.documentView = area
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let area = scroll.documentView as? FlowNSTextView else { return }
        if area.string != text {
            area.string = text
        }
        area.placeholder = placeholder
        let wanted = wantsFocus
        if area.wantsFocus != wanted {
            area.wantsFocus = wanted
            if wanted {
                FlowFocus.schedule { [weak area] in area?.claimFocus() }
            } else if area.window?.firstResponder === area {
                area.window?.makeFirstResponder(nil)
            }
        }
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        (scroll.documentView as? FlowNSTextView)?.stopWatching()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FlowTextArea

        init(_ parent: FlowTextArea) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let area = notification.object as? NSTextView else { return }
            parent.text = area.string
            area.needsDisplay = true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}

final class FlowNSTextView: NSTextView {
    var wantsFocus = true
    var placeholder = "" {
        didSet { needsDisplay = true }
    }
    var placeholderColor = NSColor.secondaryLabelColor
    private var keyObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatching()
        guard let window else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.claimFocus() }
        }
        FlowFocus.schedule { [weak self] in self?.claimFocus() }
    }

    func stopWatching() {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
    }

    func claimFocus() {
        guard wantsFocus, let window, window.firstResponder !== self else { return }
        guard FlowFocus.ensureKey(window) else { return }
        if window.makeFirstResponder(self) {
            setSelectedRange(NSRange(location: string.utf16.count, length: 0))
        }
    }

    override func draw(_ rect: NSRect) {
        super.draw(rect)
        guard string.isEmpty, !placeholder.isEmpty, let font else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: placeholderColor]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0), y: textContainerInset.height)
        (placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }
}
