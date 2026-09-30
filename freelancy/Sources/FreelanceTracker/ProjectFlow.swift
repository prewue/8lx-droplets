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

/// Shown where a project is needed but there is none.
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

            FlowActionRow(title: droplet.sessionRename?.isNewSession == true ? "Start" : "Save", accent: accent) {
                droplet.commitSessionRename()
            }
        }
    }

    /// Current name when renaming, default name for a new session.
    private var placeholder: String {
        guard let rename = droplet.sessionRename else { return "Session name" }
        if let id = rename.sessionID, let session = droplet.session(id) { return session.name }
        return droplet.defaultSessionName(on: rename.projectID)
    }

    private var accent: Color? {
        guard let rename = droplet.sessionRename, let project = droplet.project(rename.projectID) else { return nil }
        return project.color.color
    }
}

private struct FlowStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    /// Currency search text, nil while closed.
    @State private var currencyQuery: String?

    private var color: ProjectColor { droplet.draft?.color ?? draft.color }

    var body: some View {
        VStack(spacing: DroppySpacing.md) {
            FlowNav(title: title, back: { droplet.backInDraft() }, hidesTitle: currencyQuery != nil) {
                if draft.step == .currency {
                    NavSearch(query: $currencyQuery) { droplet.advanceDraft() }
                } else if draft.step == .rate {
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
            CurrencyStep(droplet: droplet, draft: draft, query: currencyQuery)
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
    /// Hides the title while the search is open.
    var hidesTitle = false
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ZStack {
            Text(verbatim: title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)
                .opacity(hidesTitle ? 0 : 1)
                .blur(radius: hidesTitle ? 4 : 0)
                .animation(.easeOut(duration: 0.16), value: hidesTitle)
            HStack(spacing: DroppySpacing.sm) {
                CornerButton(systemImage: "chevron.left", help: "Back", action: back)
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(height: FreelanceTrackerDroplet.navHeight)
    }
}

/// Search button that opens into a field across the nav row.
/// Return confirms the currency, Escape closes.
private struct NavSearch: View {
    @Binding var query: String?
    let submit: () -> Void

    @State private var isExpanded = false
    @State private var showsContent = false
    /// Ignores leftover animation steps from a previous open or close.
    @State private var generation = 0

    /// Soft spring for opening and closing.
    private static let spring = Animation.spring(response: 0.46, dampingFraction: 0.8)
    private static let iconWidth: CGFloat = 14
    private static let blurIn = AnyTransition.modifier(
        active: BlurFade(radius: 6, opacity: 0),
        identity: BlurFade(radius: 0, opacity: 1)
    )

    var body: some View {
        let shape = Capsule(style: .continuous)
        // The magnifier sits centred in the disc and slides to the left edge as it opens.
        let collapsedPadding = (FreelanceTrackerDroplet.navHeight - Self.iconWidth) / 2
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DroppyGlassControl.neutralInk())
                .frame(width: Self.iconWidth)
            if showsContent {
                FlowTextField(
                    text: Binding(get: { query ?? "" }, set: { query = $0 }),
                    placeholder: "",
                    font: .systemFont(ofSize: 13, weight: .medium),
                    onSubmit: submit,
                    onCancel: close,
                    alignment: .left
                )
                .frame(height: 20)
                .overlay(alignment: .leading) {
                    // SwiftUI placeholder so it can fade in from a blur.
                    if (query ?? "").isEmpty {
                        Text("Search currencies")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                            .padding(.leading, 2)
                            .allowsHitTesting(false)
                    }
                }
                .transition(Self.blurIn)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close search")
                .transition(Self.blurIn)
            }
        }
        .padding(.horizontal, isExpanded ? DroppySpacing.smd : collapsedPadding)
        .frame(width: isExpanded ? nil : FreelanceTrackerDroplet.navHeight, height: FreelanceTrackerDroplet.navHeight, alignment: .leading)
        .frame(maxWidth: isExpanded ? .infinity : FreelanceTrackerDroplet.navHeight, alignment: .leading)
        .droppyGlassControlChrome(shape: AnyShape(shape))
        .contentShape(shape)
        .onTapGesture {
            if !isExpanded { open() }
        }
        .help(isExpanded ? "" : "Search currencies")
        .accessibilityLabel("Search currencies")
    }

    private func open() {
        generation += 1
        let beat = generation
        withAnimation(.easeOut(duration: 0.16)) { query = "" }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard beat == generation else { return }
            withAnimation(Self.spring) { isExpanded = true }
            try? await Task.sleep(for: .milliseconds(260))
            guard beat == generation else { return }
            withAnimation(.easeOut(duration: 0.28)) { showsContent = true }
        }
    }

    private func close() {
        generation += 1
        let beat = generation
        withAnimation(.easeIn(duration: 0.12)) { showsContent = false }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard beat == generation else { return }
            withAnimation(Self.spring) { isExpanded = false }
            try? await Task.sleep(for: .milliseconds(220))
            guard beat == generation else { return }
            withAnimation(.easeOut(duration: 0.18)) { query = nil }
        }
    }
}

/// Fades in from a blur.
private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
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

/// Colour picker. Confirm applies the choice, Back drops it.
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

private struct ColorOrb: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 44, height: 44)
    }
}

/// Hourly rate: the amount (click to type it) over a ruler.
private struct RateStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft

    @State private var isTyping = false
    @State private var typed = ""
    @StateObject private var ruler = WheelEngine()

    private static let range = 1...500

    private var rate: Double { droplet.draft?.rate ?? draft.rate }
    private var currency: TrackerCurrency { droplet.draft?.currency ?? draft.currency }
    private var color: Color { (droplet.draft?.color ?? draft.color).color }

    var body: some View {
        VStack(spacing: DroppySpacing.xs) {
            Group {
                if isTyping {
                    FlowTextField(
                        text: $typed,
                        placeholder: plainNumber(rate),
                        font: .monospacedDigitSystemFont(ofSize: 26, weight: .semibold),
                        onSubmit: { finishTyping(apply: true) },
                        onCancel: { finishTyping(apply: false) },
                        onEndEditing: { finishTyping(apply: true) }
                    )
                    .frame(width: 200, height: 30)
                } else {
                    Button {
                        typed = plainNumber(rate)
                        isTyping = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(verbatim: currency.formatAmount(rate))
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(color)
                                .contentTransition(.numericText())
                            Text("/h")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Click to type an exact rate")
                    .animation(DroppyAnimation.state, value: rate)
                }
            }
            .frame(height: 30)

            RulerWheel(
                engine: ruler,
                range: Self.range,
                value: Binding(
                    get: { Int(rate.rounded()) },
                    set: { whole in droplet.updateDraft { $0.rate = Double(whole) } }
                ),
                tint: color
            )
            .accessibilityLabel("Hourly rate")
        }
        // Nudged up without changing the layout.
        .offset(y: -6)
        .background {
            if !isTyping {
                FlowKeyReceiver { key, shift in
                    switch key {
                    case .left, .down: ruler.step(shift ? -10 : -1)
                    case .right, .up: ruler.step(shift ? 10 : 1)
                    case .enter: droplet.advanceDraft()
                    case .escape: droplet.backInDraft()
                    }
                }
            }
        }
        .onChange(of: rate) { _, typedRate in
            // Move the ruler to a typed amount.
            let target = min(max(Int(typedRate.rounded()), Self.range.lowerBound), Self.range.upperBound) - Self.range.lowerBound
            if ruler.index != target { ruler.go(to: target) }
        }
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

/// Currency picker. Codes scroll under a fixed glass lens; search narrows the list.
private struct CurrencyStep: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet
    let draft: ProjectDraft
    let query: String?

    @StateObject private var wheel = WheelEngine()

    private var searchText: String {
        (query ?? "").trimmingCharacters(in: .whitespaces)
    }

    private var matches: [TrackerCurrency] {
        guard !searchText.isEmpty else { return TrackerCurrency.all }
        return TrackerCurrency.all.filter { currency in
            [currency.code, currency.name, currency.symbol].contains {
                $0.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    var body: some View {
        let found = matches
        ZStack {
            if found.isEmpty {
                Text("No currency matches")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            } else {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .frame(width: CurrencyPill.width, height: CurrencyPill.height)
                    .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)))

                InfiniteWheel(
                    engine: wheel,
                    items: found,
                    selection: Binding(
                        get: { droplet.draft?.pendingCurrency ?? draft.currency },
                        set: { chosen in droplet.updateDraft { $0.pendingCurrency = chosen } }
                    ),
                    style: .currencies,
                    wraps: searchText.isEmpty
                ) { currency, isCentred in
                    CurrencyPill(code: currency.code, isCentred: isCentred)
                        .help(currency.name)
                        .accessibilityLabel(currency.name)
                }
            }
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

/// Currency code on the wheel.
private struct CurrencyPill: View {
    let code: String
    let isCentred: Bool

    static let width: CGFloat = 64
    static let height: CGFloat = 32

    var body: some View {
        Text(verbatim: code)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(isCentred ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
            .animation(DroppyAnimation.state, value: isCentred)
            .frame(width: Self.width, height: Self.height)
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
    let onSubmit: () -> Void
    let onCancel: () -> Void
    var onEndEditing: (() -> Void)? = nil
    var alignment: NSTextAlignment = .center

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> FlowNSTextField {
        let field = FlowNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.alignment = alignment
        field.font = font
        field.textColor = NSColor(AdaptiveColors.notchSurfacePrimaryText)
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
            editor.insertionPointColor = NSColor(AdaptiveColors.notchSurfacePrimaryText)
            editor.selectedRange = NSRange(location: stringValue.utf16.count, length: 0)
        }
    }
}
