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
                }
            }

            content
                .frame(maxWidth: .infinity)
                .frame(height: FreelanceTrackerDroplet.flowBodyHeight)

            FlowActionRow(
                title: actionTitle,
                accent: draft.step == .rate ? draft.color.color : nil
            ) {
                droplet.advanceDraft()
            }
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
        }
    }

    private var title: String {
        switch draft.step {
        case .name: "Project name"
        case .look: "Choose icon"
        case .rate: "Hourly rate"
        case .currency: "Currency"
        }
    }

    private var actionTitle: String {
        switch draft.step {
        case .name, .look: "Continue"
        case .rate: draft.isEditing ? "Save" : "Create"
        case .currency: "Confirm"
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
        VStack(spacing: DroppySpacing.md) {
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

            ColorDots(
                selection: Binding(
                    get: { color },
                    set: { chosen in droplet.updateDraft { $0.color = chosen } }
                )
            )
            .frame(height: 20)
        }
        .background {
            FlowKeyReceiver { key, shift in
                switch key {
                case .left: wheel.step(-1)
                case .right: wheel.step(1)
                case .up: cycleColor(-1)
                case .down: cycleColor(1)
                case .enter: droplet.advanceDraft()
                case .escape: droplet.backInDraft()
                }
            }
        }
    }

    private func cycleColor(_ delta: Int) {
        let all = ProjectColor.allCases
        guard let index = all.firstIndex(of: color) else { return }
        let next = all[(index + delta + all.count) % all.count]
        withAnimation(DroppyAnimation.segmentedSelection) {
            droplet.updateDraft { $0.color = next }
        }
    }
}

private struct ColorDots: View {
    @Binding var selection: ProjectColor

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            ForEach(ProjectColor.allCases) { color in
                let isSelected = color == selection
                Circle()
                    .fill(color.color)
                    .frame(width: 12, height: 12)
                    .scaleEffect(isSelected ? 1.5 : 1)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
                    .onTapGesture {
                        withAnimation(DroppyAnimation.segmentedSelection) { selection = color }
                    }
                    .help(color.name)
                    .accessibilityLabel(color.name)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(DroppyAnimation.segmentedSelection, value: selection)
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

enum WheelShape {
    case icon
    case pill

    func scale(_ distance: CGFloat) -> CGFloat {
        switch self {
        case .icon: 0.42 + 0.58 * exp(-1.0 * distance)
        case .pill: 0.55 + 0.45 * exp(-1.1 * distance)
        }
    }

    func opacity(_ distance: CGFloat) -> Double {
        Double(max(0.2, 1 - 0.3 * distance))
    }

    func offset(_ t: CGFloat, pitch: CGFloat) -> CGFloat {
        let d = abs(t)
        let squeeze = d <= 3 ? 1 - 0.1 * d : 0.7
        return pitch * t * squeeze
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

    func go(to virtualIndex: Int) {
        snapTask?.cancel()
        settle(on: CGFloat(virtualIndex))
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

    private static var fadeWidth: CGFloat { 96 }
    private static var reach: Int { 6 }

    var body: some View {
        let position = engine.position
        let centre = Int(position.rounded())
        ZStack {
            ForEach((centre - Self.reach)...(centre + Self.reach), id: \.self) { virtual in
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
                    .frame(width: Self.fadeWidth)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fadeWidth)
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

final class FlowKeyView: NSView {
    var handler: ((FlowKey, Bool) -> Void)?
    private var keyObserver: NSObjectProtocol?

    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
        guard let window, window.firstResponder !== self else { return }
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return }
        guard FlowFocus.ensureKey(window) else { return }
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let shift = event.modifierFlags.contains(.shift)
        let key: FlowKey?
        switch event.keyCode {
        case 123: key = .left
        case 124: key = .right
        case 126: key = .up
        case 125: key = .down
        case 36, 76: key = .enter
        case 53: key = .escape
        default: key = nil
        }
        if let key, let handler {
            handler(key, shift)
        } else {
            super.keyDown(with: event)
        }
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
