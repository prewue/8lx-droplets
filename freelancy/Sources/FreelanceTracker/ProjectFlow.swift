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

/// A screen that needs a project when there is none: the start screen.
struct NoProjectScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    var body: some View {
        StartScreen(droplet: droplet)
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
            style: .icons
        ) { icon, isCentred in
            Image(systemName: icon.symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(isCentred ? color.color : AdaptiveColors.notchSurfaceSecondaryText)
                .frame(width: 48, height: 44)
                .accessibilityLabel(icon.name)
        }
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
            style: .colors
        ) { color, _ in
            ColorOrb(color: color.color)
                .help(color.name)
                .accessibilityLabel(color.name)
        }
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

/// One colour of the wheel: a plain disc of it.
private struct ColorOrb: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 44, height: 44)
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
            style: .currencies
        ) { currency, isCentred in
            CurrencyPill(code: currency.code, isCentred: isCentred)
                .help(currency.name)
                .accessibilityLabel(currency.name)
        }
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

/// A currency code in a glass capsule; a flat capsule in the edge blur's copies, where glass
/// would cost a lot and show nothing.
private struct CurrencyPill: View {
    let code: String
    let isCentred: Bool

    @Environment(\.wheelBlurCopy) private var isBlurCopy

    var body: some View {
        let shape = Capsule(style: .continuous)
        let label = Text(verbatim: code)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isCentred ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
            .frame(width: 64, height: 32)
        if isBlurCopy {
            label.background(shape.fill(AdaptiveColors.overlayAuto(0.1)))
        } else if isCentred {
            label.droppyGlassControlChrome(shape: AnyShape(shape), fill: .veil)
        } else {
            label
                .droppyGlassControlChrome(shape: AnyShape(shape), fill: .veil)
                .droppyFlatGlassControls()
        }
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
