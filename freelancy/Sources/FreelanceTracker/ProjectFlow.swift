import AppKit
import DroppyKit
import SwiftUI

struct ProjectFlowScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        if let draft = droplet.draft {
            ZStack(alignment: .top) {
                FlowStep(droplet: droplet, draft: draft)
                    .id(draft.step)
                    .transition(DroppyTransition.element)
            }
            .animation(DroppyAnimation.state, value: draft.step)
        } else {
            NoProjectScreen(droplet: droplet)
        }
    }
}

struct NoProjectScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            Text("No projects yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            Button {
                droplet.startNewProject()
            } label: {
                Text("New project")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, DroppySpacing.lg)
                    .frame(height: FreelanceTrackerDroplet.flowActionHeight)
            }
            .buttonStyle(DroppyGlassButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SessionRenameScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    private static let maxLength = 40

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            FlowNav(title: "Session name", back: { droplet.cancelSessionRename() }) {
                EmptyView()
            }

            FlowTextField(
                text: Binding(
                    get: { droplet.sessionRename?.name ?? "" },
                    set: { droplet.updateSessionRename(String($0.prefix(Self.maxLength))) }
                ),
                placeholder: placeholder,
                font: .systemFont(ofSize: 26, weight: .semibold),
                onSubmit: { droplet.commitSessionRename() },
                onCancel: { droplet.cancelSessionRename() }
            )
            .frame(height: 34)
            .padding(.horizontal, DroppySpacing.xxl)
            .frame(maxWidth: .infinity)
            .frame(height: FreelanceTrackerDroplet.flowBodyHeight)
            .accessibilityLabel("Session name")

            FlowActionRow(title: "Save", accent: accent) {
                droplet.commitSessionRename()
            }
        }
    }

    private var placeholder: String {
        guard let id = droplet.sessionRename?.sessionID, let session = droplet.session(id) else { return "Session name" }
        return session.name
    }

    private var accent: Color? {
        guard let id = droplet.sessionRename?.sessionID,
              let session = droplet.session(id),
              let project = droplet.project(session.projectID) else { return nil }
        return project.color.color
    }
}

private struct FlowStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    private var color: ProjectColor { droplet.draft?.color ?? draft.color }

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            FlowNav(title: title, back: { droplet.backInDraft() }) {
                if draft.step == .rate {
                    Button {
                        droplet.setDraftStep(.currency)
                    } label: {
                        Text(verbatim: draft.currency.code)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, DroppySpacing.md)
                            .frame(height: FreelanceTrackerDroplet.navHeight)
                    }
                    .buttonStyle(DroppyGlassButtonStyle())
                    .help("Change the currency, \(draft.currency.name)")
                    .accessibilityLabel("Currency, \(draft.currency.name)")
                } else if draft.step == .look {
                    Button {
                        droplet.setDraftStep(.color)
                    } label: {
                        Text("Color")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, DroppySpacing.md)
                            .frame(height: FreelanceTrackerDroplet.navHeight)
                    }
                    .buttonStyle(VividGlassButtonStyle(accent: color.color))
                    .help("Change the colour, \(color.name)")
                    .accessibilityLabel("Colour, \(color.name)")
                }
            }

            content
                .frame(maxWidth: .infinity)
                .frame(height: FreelanceTrackerDroplet.flowBodyHeight)

            FlowActionRow(title: actionTitle, accent: actionAccent) {
                droplet.advanceDraft()
            }
        }
    }

    private var actionAccent: Color? {
        switch draft.step {
        case .rate: draft.color.color
        case .color: (droplet.draft?.pendingColor ?? draft.color).color
        default: nil
        }
    }

    @ViewBuilder
    private var content: some View {
        switch draft.step {
        case .name:
            NameStep(droplet: droplet, draft: draft)
        case .look:
            LookStep(droplet: droplet, draft: draft)
        case .rate:
            RateStep(droplet: droplet, draft: draft)
        case .currency:
            CurrencyStep(droplet: droplet, draft: draft)
        case .color:
            ColorStep(droplet: droplet, draft: draft)
        }
    }

    private var title: String {
        switch draft.step {
        case .name: "Project name"
        case .look: "Choose icon"
        case .rate: "Hourly rate"
        case .currency: "Currency"
        case .color: "Choose color"
        }
    }

    private var actionTitle: String {
        switch draft.step {
        case .name, .look: "Continue"
        case .rate: draft.isEditing ? "Save" : "Create"
        case .currency, .color: "Confirm"
        }
    }
}

private struct FlowNav<Trailing: View>: View {
    let title: String
    let back: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            HStack {
                CornerButton(systemImage: "chevron.left", help: "Back", action: back)
                Spacer(minLength: 0)
                trailing()
            }
            Text(verbatim: title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)
        }
        .frame(height: FreelanceTrackerDroplet.navHeight)
    }
}

private struct FlowActionRow: View {
    let title: String
    let accent: Color?
    let action: () -> Void

    var body: some View {
        HStack(spacing: DroppySpacing.md) {
            Button(action: action) {
                Text(verbatim: title)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, DroppySpacing.xl)
                    .frame(height: FreelanceTrackerDroplet.flowActionHeight)
            }
            .buttonStyle(VividGlassButtonStyle(accent: accent))

            HStack(spacing: DroppySpacing.xs) {
                Text("or")
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                Text("Press")
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                Image(systemName: "return")
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }
            .font(.system(size: 12, weight: .medium))
            .accessibilityHidden(true)
        }
        .frame(height: FreelanceTrackerDroplet.flowActionHeight)
    }
}

struct VividGlassButtonStyle: ButtonStyle {
    let accent: Color?
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        VividGlassLabel(configuration: configuration, accent: accent, destructive: destructive)
    }
}

private struct VividGlassLabel: View {
    let configuration: ButtonStyleConfiguration
    let accent: Color?
    let destructive: Bool

    @State private var isHovering = false

    var body: some View {
        let shape = Capsule(style: .continuous)
        configuration.label
            .foregroundStyle(DroppyGlassControl.neutralInk())
            .droppyGlassControlChrome(
                shape: AnyShape(shape),
                fill: accent.map { .tinted($0) } ?? (destructive ? .tinted(.red) : .veil),
                isHovering: isHovering,
                isPressed: configuration.isPressed
            )
            .background {
                if let accent {
                    shape.fill(accent.opacity(configuration.isPressed ? 0.62 : (isHovering ? 0.56 : 0.48)))
                }
            }
            .onHover { isHovering = $0 }
            .animation(DroppyAnimation.hover, value: isHovering)
    }
}

private struct NameStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    private static let maxLength = 40

    var body: some View {
        FlowTextField(
            text: Binding(
                get: { droplet.draft?.name ?? "" },
                set: { text in droplet.updateDraft { $0.name = String(text.prefix(Self.maxLength)) } }
            ),
            placeholder: draft.isEditing ? "Project name" : droplet.draftPlaceholderName,
            font: .systemFont(ofSize: 26, weight: .semibold),
            onSubmit: { droplet.advanceDraft() },
            onCancel: { droplet.backInDraft() }
        )
        .frame(height: 34)
        .padding(.horizontal, DroppySpacing.xxl)
        .accessibilityLabel("Project name")
    }
}

private struct LookStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    @StateObject private var wheel = WheelEngine()

    private var color: ProjectColor { droplet.draft?.color ?? draft.color }

    var body: some View {
        InfiniteWheel(
            engine: wheel,
            items: ProjectIcon.allCases,
            selection: Binding(
                get: { droplet.draft?.icon ?? draft.icon },
                set: { icon in droplet.updateDraft { $0.icon = icon } }
            ),
            pitch: 56,
            shape: .icon
        ) { icon, isCentred in
            Image(systemName: icon.symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isCentred ? color.color : AdaptiveColors.notchSurfaceSecondaryText)
                .frame(width: 48, height: 44)
                .accessibilityLabel(icon.name)
        }
        .frame(height: 44)
        .background {
            FlowKeyReceiver { key, _ in
                switch key {
                case .left: wheel.step(-1)
                case .right: wheel.step(1)
                case .up, .down: break
                case .enter: droplet.advanceDraft()
                case .escape: droplet.backInDraft()
                }
            }
        }
    }
}

/// The colour wheel, opened from the icon step's Color pill: the icon wheel's row, centred, the
/// colours softening towards the edges. `pendingColor` holds the choice; Confirm applies it,
/// Back drops it, as the currency step does.
private struct ColorStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    @StateObject private var wheel = WheelEngine()

    var body: some View {
        InfiniteWheel(
            engine: wheel,
            items: ProjectColor.allCases,
            selection: Binding(
                get: { droplet.draft?.pendingColor ?? draft.color },
                set: { chosen in droplet.updateDraft { $0.pendingColor = chosen } }
            ),
            pitch: 56,
            shape: .orb
        ) { color, _ in
            ColorOrb(color: color.color)
                .help(color.name)
                .accessibilityLabel(color.name)
        }
        .frame(height: 56)
        .background {
            FlowKeyReceiver { key, _ in
                switch key {
                case .left, .up: wheel.step(-1)
                case .right, .down: wheel.step(1)
                case .enter: droplet.advanceDraft()
                case .escape: droplet.backInDraft()
                }
            }
        }
    }
}

/// One colour of the wheel: a glass pill tinted its colour, over a dense disc of the same colour
/// so the glass reads at full saturation.
private struct ColorOrb: View {
    let color: Color

    @Environment(\.wheelBlurCopy) private var isBlurCopy

    var body: some View {
        let shape = Circle()
        if isBlurCopy {
            shape
                .fill(color.opacity(0.85))
                .frame(width: 44, height: 44)
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .droppyGlassControlChrome(shape: AnyShape(shape), fill: .tinted(color))
                .background(shape.fill(color.opacity(0.7)))
                .saturation(1.2)
        }
    }
}

private struct RateStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    @State private var isTyping = false
    @State private var typed = ""

    private static let range: ClosedRange<Double> = 1...500

    private var rate: Double { droplet.draft?.rate ?? draft.rate }
    private var currency: TrackerCurrency { droplet.draft?.currency ?? draft.currency }

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            Group {
                if isTyping {
                    FlowTextField(
                        text: $typed,
                        placeholder: plainNumber(rate),
                        font: .monospacedDigitSystemFont(ofSize: 30, weight: .semibold),
                        onSubmit: { finishTyping(apply: true) },
                        onCancel: { finishTyping(apply: false) },
                        onEndEditing: { finishTyping(apply: true) }
                    )
                    .frame(width: 200, height: 38)
                } else {
                    Button {
                        typed = plainNumber(rate)
                        isTyping = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(verbatim: currency.formatAmount(rate))
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                                .contentTransition(.numericText())
                            Text("/h")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click to type an exact rate")
                    .animation(DroppyAnimation.state, value: rate)
                }
            }
            .frame(height: 38)

            Slider(
                value: Binding(
                    get: { min(max(rate, Self.range.lowerBound), Self.range.upperBound) },
                    set: { value in droplet.updateDraft { $0.rate = value.rounded() } }
                ),
                in: Self.range
            )
            .controlSize(.small)
            .tint(AdaptiveColors.notchSurfacePrimaryText)
            .frame(width: 240)
            .accessibilityLabel("Hourly rate")
        }
        .background {
            if !isTyping {
                FlowKeyReceiver { key, shift in
                    switch key {
                    case .left, .down: nudge(shift ? -10 : -1)
                    case .right, .up: nudge(shift ? 10 : 1)
                    case .enter: droplet.advanceDraft()
                    case .escape: droplet.backInDraft()
                    }
                }
            }
        }
    }

    private func nudge(_ delta: Double) {
        droplet.updateDraft { $0.rate = max(0, ($0.rate + delta).rounded()) }
    }

    private func plainNumber(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func finishTyping(apply: Bool) {
        guard isTyping else { return }
        isTyping = false
        guard apply else { return }
        let cleaned = typed
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        if let value = Double(cleaned), value.isFinite, value >= 0 {
            droplet.updateDraft { $0.rate = min((value * 100).rounded() / 100, 1_000_000) }
        }
    }
}

private struct CurrencyStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    @StateObject private var wheel = WheelEngine()

    var body: some View {
        InfiniteWheel(
            engine: wheel,
            items: TrackerCurrency.all,
            selection: Binding(
                get: { droplet.draft?.pendingCurrency ?? draft.currency },
                set: { chosen in droplet.updateDraft { $0.pendingCurrency = chosen } }
            ),
            pitch: 104,
            shape: .pill
        ) { currency, isCentred in
            CurrencyPill(code: currency.code, isCentred: isCentred)
                .help(currency.name)
                .accessibilityLabel(currency.name)
        }
        .frame(height: 50)
        .background {
            FlowKeyReceiver { key, _ in
                switch key {
                case .left, .up: wheel.step(-1)
                case .right, .down: wheel.step(1)
                case .enter: droplet.advanceDraft()
                case .escape: droplet.backInDraft()
                }
            }
        }
    }
}

private struct CurrencyPill: View {
    let code: String
    let isCentred: Bool

    var body: some View {
        let label = Text(verbatim: code)
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(isCentred ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
            .frame(width: 92, height: 46)
            .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)), fill: .veil)
        if isCentred {
            label
        } else {
            label.droppyFlatGlassControls()
        }
    }
}

/// How a wheel draws an item `t` steps from the centre (`distance` is `|t|`). Every curve is
/// smooth through the whole ring, like a drum turning: no step where an item's speed, size or
/// softness changes all at once.
enum WheelShape {
    case icon
    case pill
    /// The colour wheel: the icon wheel's geometry, softening a little more towards the edges.
    case orb

    func scale(_ distance: CGFloat) -> CGFloat {
        switch self {
        case .icon, .orb: 0.45 + 0.55 * Self.bell(distance, width: 1.1)
        case .pill: 0.55 + 0.45 * Self.bell(distance, width: 1.2)
        }
    }

    func opacity(_ distance: CGFloat) -> Double {
        Double(0.2 + 0.8 * Self.bell(distance, width: 1.3))
    }

    /// The row gathers towards its ends on a `tanh`, full pitch at the centre, so an item slows
    /// smoothly as it travels out instead of changing speed at a fixed step.
    func offset(_ t: CGFloat, pitch: CGFloat) -> CGFloat {
        let reach = pitch * 4.3
        return reach * tanh(t * pitch / reach)
    }

    /// The strongest blur at the wheel's outer edges (`ProgressiveEdgeBlur`); none for pills.
    var edgeBlur: CGFloat {
        switch self {
        case .pill: 0
        case .icon: 4
        case .orb: 6
        }
    }

    /// How far in from each edge the blur reaches, well past the fade: the blur, not the fade,
    /// does most of the softening on the icon and colour wheels.
    var edgeBlurBand: CGFloat {
        switch self {
        case .pill, .icon: 150
        case .orb: 180
        }
    }

    /// The dark fade at each edge: short where the blur softens the edge, long for the pills.
    var fadeWidth: CGFloat {
        switch self {
        case .pill: 96
        case .icon, .orb: 56
        }
    }

    /// 1 at the centre, falling as a Gaussian of the given width: flat at the top, so the item
    /// in the middle eases in and out of its full size rather than popping.
    private static func bell(_ distance: CGFloat, width: CGFloat) -> CGFloat {
        exp(-(distance * distance) / (2 * width * width))
    }
}

@MainActor
final class WheelEngine: ObservableObject {
    @Published var position: CGFloat = 0

    var count = 1
    var pitch: CGFloat = 56
    var onIndexChange: ((Int) -> Void)?
    var isHovering = false

    private var monitor: Any?
    private var snapTask: Task<Void, Never>?
    private var dragStart: CGFloat?
    private var lastIndex: Int?

    var index: Int { wrap(Int(position.rounded())) }

    func wrap(_ value: Int) -> Int {
        ((value % count) + count) % count
    }

    func place(at index: Int) {
        let base = Int(position.rounded())
        var delta = index - wrap(base)
        if delta > count / 2 { delta -= count }
        if delta < -count / 2 { delta += count }
        position = CGFloat(base + delta)
        lastIndex = index
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let precise = event.hasPreciseScrollingDeltas
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.isHovering else { return false }
                self.scroll(precise: precise, dx: dx, dy: dy)
                return true
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        snapTask?.cancel()
        snapTask = nil
    }

    private func scroll(precise: Bool, dx: CGFloat, dy: CGFloat) {
        if precise {
            let delta = abs(dx) >= abs(dy) ? dx : dy
            guard delta != 0 else { return }
            snapTask?.cancel()
            position -= delta / pitch
            report(haptic: true)
            scheduleSnap()
        } else {
            let delta = dy != 0 ? dy : dx
            guard delta != 0 else { return }
            step(delta > 0 ? -1 : 1)
        }
    }

    private func scheduleSnap() {
        snapTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            self.settle(on: self.position.rounded())
        }
    }

    func step(_ delta: Int) {
        snapTask?.cancel()
        settle(on: position.rounded() + CGFloat(delta))
    }

    /// A click on an item further along glides there, longer the further it is, instead of
    /// springing across the gap in one leap.
    func go(to virtualIndex: Int) {
        snapTask?.cancel()
        let distance = abs(CGFloat(virtualIndex) - position)
        guard distance > 1.5 else {
            settle(on: CGFloat(virtualIndex))
            return
        }
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: min(0.3 + 0.09 * Double(distance), 0.75))) {
            position = CGFloat(virtualIndex)
        }
        report(haptic: false)
    }

    func dragChanged(_ translation: CGFloat) {
        if dragStart == nil {
            dragStart = position
            snapTask?.cancel()
        }
        position = (dragStart ?? position) - translation / pitch
        report(haptic: true)
    }

    func dragEnded(_ predictedTranslation: CGFloat) {
        let start = dragStart ?? position
        dragStart = nil
        settle(on: (start - predictedTranslation / pitch).rounded())
    }

    private func settle(on target: CGFloat) {
        withAnimation(DroppyAnimation.stateEmphasis) { position = target }
        report(haptic: false)
    }

    private func report(haptic: Bool) {
        let current = index
        guard current != lastIndex else { return }
        lastIndex = current
        if haptic {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        onIndexChange?(current)
    }
}

struct InfiniteWheel<Item: Hashable, Cell: View>: View {
    @ObservedObject var engine: WheelEngine
    let items: [Item]
    @Binding var selection: Item
    let pitch: CGFloat
    let shape: WheelShape
    @ViewBuilder let cell: (Item, Bool) -> Cell

    @State private var width: CGFloat = 0

    private static var reach: Int { 6 }

    /// The items a copy of the edge blur draws: all of them for the sharp copy, and for a blurred
    /// one only those that reach into the part of the band it covers, so the copies that exist
    /// for the outer edge draw an item or two instead of the whole ring.
    private func virtuals(for copy: EdgeBlurCopy, position: CGFloat) -> [Int] {
        let centre = Int(position.rounded())
        let all = Array((centre - Self.reach)...(centre + Self.reach))
        guard copy.step > 0, width > 0 else { return all }
        let threshold = width / 2 - copy.reach - pitch / 2
        return all.filter { abs(shape.offset(CGFloat($0) - position, pitch: pitch)) >= threshold }
    }

    var body: some View {
        let position = engine.position
        ProgressiveEdgeBlur(maxRadius: shape.edgeBlur, band: shape.edgeBlurBand) { copy in
            ZStack {
                ForEach(virtuals(for: copy, position: position), id: \.self) { virtual in
                    let t = CGFloat(virtual) - position
                    let distance = abs(t)
                    cell(items[engine.wrap(virtual)], distance < 0.5)
                        .scaleEffect(shape.scale(distance))
                        .opacity(shape.opacity(distance))
                        .offset(x: shape.offset(t, pitch: pitch))
                        .zIndex(-Double(distance))
                        .onTapGesture { engine.go(to: virtual) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { engine.dragChanged($0.translation.width) }
                .onEnded { engine.dragEnded($0.predictedEndTranslation.width) }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active: engine.isHovering = true
            case .ended: engine.isHovering = false
            }
        }
        .mask(
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: shape.fadeWidth)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: shape.fadeWidth)
            }
        )
        .onAppear {
            engine.count = items.count
            engine.pitch = pitch
            if let index = items.firstIndex(of: selection) { engine.place(at: index) }
            engine.onIndexChange = { index in
                let chosen = items[index]
                if chosen != selection {
                    withAnimation(DroppyAnimation.segmentedSelection) { selection = chosen }
                }
            }
            engine.start()
        }
        .onDisappear { engine.stop() }
    }
}

/// A blur that grows towards the left and right edges by screen position, the way a system
/// progressive blur does, built from public SwiftUI: the content is drawn `steps + 1` times at
/// rising radii, each copy masked to a triangular weight across the edge band, and the copies
/// are added (`plusLighter`) so the weights sum to one everywhere and the blur changes
/// continuously with x. Only the sharp copy takes clicks or reaches VoiceOver.
///
/// It stays cheap by drawing as little as it can: `content` learns which copy it draws, so it
/// can leave out what that copy's mask throws away (`EdgeBlurCopy.reach`), and blurred copies carry
/// `wheelBlurCopy` so a cell can drop its glass there, where nobody could tell.
struct ProgressiveEdgeBlur<Content: View>: View {
    let maxRadius: CGFloat
    let band: CGFloat
    @ViewBuilder let content: (EdgeBlurCopy) -> Content

    private static var steps: Int { 3 }

    var body: some View {
        if maxRadius <= 0 {
            content(EdgeBlurCopy(step: 0, reach: .infinity))
        } else {
            ZStack {
                ForEach(0...Self.steps, id: \.self) { step in
                    content(copy(step))
                        .environment(\.wheelBlurCopy, step != 0)
                        .blur(radius: radius(step))
                        .mask(weight(step))
                        .blendMode(step == 0 ? .normal : .plusLighter)
                        .allowsHitTesting(step == 0)
                        .accessibilityHidden(step != 0)
                }
            }
            .compositingGroup()
        }
    }

    private func copy(_ step: Int) -> EdgeBlurCopy {
        guard step > 0 else { return EdgeBlurCopy(step: 0, reach: .infinity) }
        let inner = CGFloat(step - 1) / CGFloat(Self.steps)
        return EdgeBlurCopy(step: step, reach: band * (1 - inner) + radius(step) * 2)
    }

    /// Radii rise slowly first, so the blur eases in from the inner edge of the band.
    private func radius(_ step: Int) -> CGFloat {
        maxRadius * pow(CGFloat(step) / CGFloat(Self.steps), 1.6)
    }

    /// This copy's share of each point: 1 where the band is at its level, falling linearly to 0
    /// at the neighbouring levels. Level 0 (sharp) also owns the middle.
    private func weight(_ step: Int) -> some View {
        HStack(spacing: 0) {
            bandGradient(step, mirrored: false).frame(width: band)
            Rectangle().fill(step == 0 ? Color.black : Color.clear)
            bandGradient(step, mirrored: true).frame(width: band)
        }
    }

    /// Across a band from its inner edge (level 0) to the outer edge (level `steps`).
    private func bandGradient(_ step: Int, mirrored: Bool) -> LinearGradient {
        let stops = (0...Self.steps).map { level in
            let inner = CGFloat(level) / CGFloat(Self.steps)
            return Gradient.Stop(
                color: level == step ? .black : .clear,
                location: mirrored ? inner : 1 - inner
            )
        }
        .sorted { $0.location < $1.location }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

/// Which copy of `ProgressiveEdgeBlur` a view is drawing.
struct EdgeBlurCopy {
    /// 0 is the sharp copy; the highest step the most blurred.
    let step: Int
    /// How far in from each outer edge this copy's mask reaches, with room for its blur.
    let reach: CGFloat
}

extension EnvironmentValues {
    /// True inside a blurred copy of `ProgressiveEdgeBlur`: a cell draws its cheap face there.
    @Entry var wheelBlurCopy = false
}

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

    /// Asks the host to make the shelf panel key; set while the droplet is active.
    /// The host owns key status (DroppyKit 1.10.0), so the flow never calls `makeKey()`.
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

/// Turns the arrows, Return and Escape into callbacks for a step with no text field.
///
/// It listens through a local key monitor rather than as first responder: a click on the step
/// (a colour, an icon, the wheel) hands first responder to the SwiftUI hosting view, which
/// drops Return, and a view that had to win first responder back lost Return for good once
/// its retries ran out. Only the newest receiver answers, because a step fading out and the
/// one fading in are both on screen for a moment, and a field editor keeps its own keys.
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
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var onEndEditing: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FlowNSTextField {
        let field = FlowNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = .center
        field.font = font
        field.textColor = .white
        field.appearance = NSAppearance(named: .darkAqua)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderAttributedString = placeholderString
        return field
    }

    func updateNSView(_ field: FlowNSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text, field.currentEditor() == nil || text.isEmpty {
            field.stringValue = text
        }
        field.placeholderAttributedString = placeholderString
    }

    static func dismantleNSView(_ field: FlowNSTextField, coordinator: Coordinator) {
        field.stopWatching()
    }

    private var placeholderString: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: placeholder, attributes: [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.32),
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

    private func claimFocus() {
        guard let window, currentEditor() == nil else { return }
        guard FlowFocus.ensureKey(window) else { return }
        if window.makeFirstResponder(self), let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .white
            editor.selectedRange = NSRange(location: stringValue.utf16.count, length: 0)
        }
    }
}
