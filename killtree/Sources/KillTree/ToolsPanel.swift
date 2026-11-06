import AppKit
import DroppyKit
import SwiftUI

/// The disc in the list's corner, and the panel it opens into.
struct ToolsCorner: View {
    @ObservedObject var droplet: KillTreeDroplet
    let context: ShelfWidgetContext

    var body: some View {
        ToolsMorph(progress: droplet.isToolsOpen ? 1 : 0, droplet: droplet, power: droplet.power)
            // A solo card on the island has no inset of its own.
            .padding([.bottom, .trailing], context.contentInsets.bottom > 0 ? 0 : ToolsMetrics.islandMargin)
    }
}

enum ToolsMetrics {
    static let discSize: CGFloat = 34
    /// Off the shell's own edge on the island, where the card has no inset.
    static let islandMargin: CGFloat = DroppySpacing.sm
    static let panelWidth: CGFloat = 232
    static let panelPadding: CGFloat = DroppySpacing.xsm
    static let cardRadius: CGFloat = DroppyRadius.medium
    static let cardHeight: CGFloat = 68
    static let closeHeight: CGFloat = 36
    static let panelHeight: CGFloat = panelPadding * 4 + cardHeight * 2 + closeHeight
    /// The list keeps this free under its last row, so the disc covers no row
    /// that can be scrolled out from under it.
    static let listFooter: CGFloat = discSize + DroppySpacing.sm
}

/// One surface all the way, so the disc's shape flows into the panel's: every
/// frame of the spring computes its own size and corner.
private struct ToolsMorph: View, Animatable {
    var progress: CGFloat
    @ObservedObject var droplet: KillTreeDroplet
    @ObservedObject var power: SleepControl

    @State private var isHovering = false

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private var discHelp: String {
        if power.lidClosed { return "Options. Lid closed mode is on." }
        if power.keepsAwake { return "Options. Keep awake is on." }
        return "Options"
    }

    var body: some View {
        let open = max(progress, 0)
        let clamped = min(open, 1)
        let size = ToolsMetrics.discSize
        let shape = RoundedRectangle(
            cornerRadius: size / 2 + (ToolsMetrics.cardRadius + ToolsMetrics.panelPadding - size / 2) * clamped,
            style: .continuous
        )
        // The disc's symbol is gone before the panel's content comes in.
        let glyph = max(1 - clamped / 0.3, 0)
        let content = max((clamped - 0.2) / 0.8, 0)
        ZStack(alignment: .bottomTrailing) {
            ToolsPanel(droplet: droplet, power: power)
                .frame(width: ToolsMetrics.panelWidth, height: ToolsMetrics.panelHeight)
                // Past the end of the spring the content swells with the surface.
                .scaleEffect(0.92 + 0.08 * content + max(open - 1, 0), anchor: .bottomTrailing)
                .blur(radius: 14 * (1 - content))
                .opacity(content)
                .allowsHitTesting(droplet.isToolsOpen)
            Button { droplet.setToolsOpen(true) } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: size, height: size)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .blur(radius: 3 * (1 - glyph))
            .opacity(glyph)
            .allowsHitTesting(!droplet.isToolsOpen)
            .onHover { isHovering = $0 }
            .help(discHelp)
            .accessibilityLabel(discHelp)
            if power.isActive {
                // Lid closed mode needs watching, so it has a colour of its own.
                Circle()
                    .fill(power.lidClosed ? Color.orange : Color.green)
                    .frame(width: DroppySpacing.xsm, height: DroppySpacing.xsm)
                    .padding(5)
                    .frame(width: size, height: size, alignment: .topTrailing)
                    .opacity(glyph)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(DroppyAnimation.state, value: power.isActive)
        .animation(DroppyAnimation.state, value: power.lidClosed)
        .frame(
            width: size + (ToolsMetrics.panelWidth - size) * open,
            height: size + (ToolsMetrics.panelHeight - size) * open,
            alignment: .bottomTrailing
        )
        .droppyGlassControlChrome(shape: AnyShape(shape), fill: .veil, isHovering: isHovering && !droplet.isToolsOpen)
        // Under the glass, so the list does not read through the panel.
        .background { shape.fill(AdaptiveColors.notchSurfaceCardFill).background(shape.fill(Color.black)) }
        .background {
            if droplet.isToolsOpen {
                ToolsDismissMonitor { droplet.setToolsOpen(false) }
            }
        }
    }
}

/// Each list has its own switches and its own way to close the lot.
private struct ToolsPanel: View {
    @ObservedObject var droplet: KillTreeDroplet
    @ObservedObject var power: SleepControl

    var body: some View {
        VStack(spacing: ToolsMetrics.panelPadding) {
            switch droplet.selectedTab {
            case .apps:
                card("Show every app", "Lists apps with nothing in the background", droplet.showsAllBinding)
                card("Keep them closed", "Closes helpers again if they come back", droplet.guardsBinding)
                CloseAllButton(title: "Close leftovers", help: "Close what is left of apps that are not open", isEnabled: droplet.canCloseAll) { droplet.closeAll() }
            case .terminal:
                ToolCard(
                    title: "Keep awake",
                    subtitle: "Prevents sleep while the lid is open",
                    isOn: power.keepsAwake,
                    set: droplet.setKeepsAwake
                )
                ToolCard(
                    title: "Lid closed mode",
                    subtitle: "Stays awake with the lid closed",
                    isOn: power.lidWanted ?? power.lidClosed,
                    isEnabled: power.lidWanted == nil,
                    set: droplet.setLidClosed
                )
                CloseAllButton(title: "Close all", help: "Close every terminal in this list", isEnabled: droplet.canCloseAll) { droplet.closeAll() }
            case .servers:
                card("Include services", "Stop all also stops launchd services", droplet.includesServicesBinding)
                card("Stay stopped", "Services stay off after a restart", droplet.persistsBinding)
                CloseAllButton(title: "Stop all", help: "Stop the servers in this list", isEnabled: droplet.canCloseAll) { droplet.closeAll() }
            }
        }
        .padding(ToolsMetrics.panelPadding)
    }

    private func card(_ title: String, _ subtitle: String, _ value: Binding<Bool>) -> some View {
        ToolCard(title: title, subtitle: subtitle, isOn: value.wrappedValue) { isOn in
            droplet.host?.feedback.play(.tick)
            value.wrappedValue = isOn
        }
    }
}

private struct ToolCard: View {
    let title: String
    let subtitle: String
    let isOn: Bool
    var isEnabled = true
    let set: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DroppySpacing.sm) {
            VStack(alignment: .leading, spacing: DroppySpacing.xs) {
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                Text(verbatim: subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            LensSwitch(title: title, isOn: isOn, isEnabled: isEnabled, set: set)
        }
        .padding(DroppySpacing.smd)
        .padding(.leading, DroppySpacing.xs)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: ToolsMetrics.cardHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: ToolsMetrics.cardRadius, style: .continuous)
                .fill(AdaptiveColors.notchSurfaceCardFill)
        )
    }
}

/// Closes the whole list. Held like Hold to Kill: it fills from the left and
/// fires once full; let go before that, nothing happens.
private struct CloseAllButton: View {
    let title: String
    let help: String
    let isEnabled: Bool
    let closeAll: () -> Void

    private static let holdTime: Double = 1

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var isHovering = false
    @State private var hold: Task<Void, Never>?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ToolsMetrics.cardRadius, style: .continuous)
        let red = KillTreeDroplet.closeTint
        // "Hold to" blurs in and pushes the rest over, which never redraws.
        HStack(spacing: DroppySpacing.xs) {
            let asksToHold = isEnabled && (isHovering || isHolding)
            if asksToHold {
                Text(verbatim: "Hold to")
                    .transition(.blurFade)
            }
            Text(verbatim: asksToHold ? title.lowercased() : title)
                .contentTransition(.interpolate)
        }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(red)
            .frame(maxWidth: .infinity)
            .frame(height: ToolsMetrics.closeHeight)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(red.opacity(0.32))
                        .frame(width: proxy.size.width * progress)
                }
            }
            .background(red.opacity(0.16))
            .clipShape(shape)
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovering = $0 }
            .animation(DroppyAnimation.controlMorph, value: isHovering)
            .animation(DroppyAnimation.controlMorph, value: isHolding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if isEnabled, !isHolding { begin() }
                    }
                    .onEnded { _ in release() }
            )
            .onDisappear { release() }
            .help(isEnabled ? "Hold: \(help)" : "Nothing to close in this list")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if isEnabled { closeAll() } }
    }

    private func begin() {
        isHolding = true
        withAnimation(.linear(duration: Self.holdTime)) { progress = 1 }
        hold = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.holdTime))
            guard !Task.isCancelled else { return }
            hold = nil
            closeAll()
        }
    }

    private func release() {
        hold?.cancel()
        hold = nil
        isHolding = false
        withAnimation(.easeOut(duration: 0.28)) { progress = 0 }
    }
}

// MARK: - The switch

/// A switch that moves like `CategoryTabs`' capsule, on the same springs: a
/// click lifts the thumb into a glass lens, flies it across and settles it.
/// No refraction: nothing lies under the thumb to bend.
struct LensSwitch: View {
    let title: String
    let isOn: Bool
    var isEnabled = true
    let set: (Bool) -> Void

    private static let width: CGFloat = 44
    private static let height: CGFloat = 24
    private static let inset: CGFloat = 2
    private static let thumb: CGFloat = 20
    private static let liftedWidth: CGFloat = 30
    private static let liftedHeight: CGFloat = 27
    private static let travel: CGFloat = width - inset * 2 - thumb

    @State private var position: CGFloat
    @State private var isLifted = false
    @State private var flight = 0

    init(title: String, isOn: Bool, isEnabled: Bool = true, set: @escaping (Bool) -> Void) {
        self.title = title
        self.isOn = isOn
        self.isEnabled = isEnabled
        self.set = set
        _position = State(initialValue: isOn ? Self.travel : 0)
    }

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        let track = Capsule(style: .continuous)
        Color.clear
            .frame(width: Self.width, height: Self.height)
            // Visible off too: the glass alone barely shows on the card.
            .background(track.fill(AdaptiveColors.notchSurfacePrimaryText.opacity(0.12 + 0.16 * position / Self.travel)))
            .droppyGlassControlChrome(shape: AnyShape(track), fill: .veil)
            // Over the track and past it, so the lifted lens is not cut.
            .overlay {
                SwitchThumb(isLifted: isLifted)
                    .frame(width: isLifted ? Self.liftedWidth : Self.thumb, height: isLifted ? Self.liftedHeight : Self.thumb)
                    .position(x: Self.inset + Self.thumb / 2 + position, y: Self.height / 2)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.6)
            .contentShape(track)
            .onTapGesture { if isEnabled { set(!isOn) } }
            // The thumb only ever follows the state, so a refused password
            // flies it back the same way.
            .onChange(of: isOn) { _, on in fly(to: on) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { if isEnabled { set(!isOn) } }
    }

    /// Lift at once, travel on a soft spring, settle once nearly there.
    private func fly(to on: Bool) {
        let target = on ? Self.travel : 0
        flight += 1
        let current = flight
        guard !reducesMotion else {
            withAnimation(.easeOut(duration: 0.16)) { position = target }
            return
        }
        withAnimation(.spring(response: 0.12, dampingFraction: 0.9)) { isLifted = true }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { position = target }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // A newer switch keeps the lens up.
            guard current == flight else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) { isLifted = false }
        }
    }
}

/// At rest a solid white disc; lifted, Droppy's glass with a solid rim.
private struct SwitchThumb: View {
    let isLifted: Bool

    var body: some View {
        let shape = Capsule(style: .continuous)
        ZStack {
            shape
                .fill(AdaptiveColors.notchSurfacePrimaryText)
                .opacity(isLifted ? 0 : 1)
            shape
                .fill(Color.clear)
                .droppyGlassControlChrome(shape: AnyShape(shape), fill: .veil)
                .overlay {
                    shape.strokeBorder(AdaptiveColors.notchSurfacePrimaryText.opacity(0.4), lineWidth: 1)
                }
                .opacity(isLifted ? 1 : 0)
        }
    }
}

// MARK: - Closing the panel

/// Closes the panel on a scroll, or on a click anywhere outside it. Sits behind
/// the panel at the panel's size, and exists only while the panel is open. The
/// event that closes it does nothing else in the shelf: the click that closes
/// the panel does not also press a Kill button under it.
private struct ToolsDismissMonitor: NSViewRepresentable {
    let dismiss: () -> Void

    func makeNSView(context: Context) -> ToolsDismissMonitorView {
        let view = ToolsDismissMonitorView()
        view.dismiss = dismiss
        return view
    }

    func updateNSView(_ view: ToolsDismissMonitorView, context: Context) {
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: ToolsDismissMonitorView, coordinator: ()) {
        view.stop()
    }
}

final class ToolsDismissMonitorView: NSView {
    var dismiss: (() -> Void)?
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stop()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            guard let self else { return event }
            // Local monitors run on the main thread; NSEvent is not Sendable.
            nonisolated(unsafe) let event = event
            let passes = MainActor.assumeIsolated { self.passes(event) }
            return passes ? event : nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Whether the event goes on to what is under it.
    private func passes(_ event: NSEvent) -> Bool {
        // Another of Droppy's windows: close, and let the event do its work.
        guard let window, event.window === window else {
            dismiss?()
            return true
        }
        if event.type == .scrollWheel {
            guard event.momentumPhase.isEmpty, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return true }
            dismiss?()
            return false
        }
        guard !bounds.contains(convert(event.locationInWindow, from: nil)) else { return true }
        dismiss?()
        return false
    }
}

// MARK: - Transition

private struct BlurFade: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 6 * amount)
            .opacity(1 - amount)
    }
}

extension AnyTransition {
    /// Comes in out of a blur and leaves into one.
    fileprivate static var blurFade: AnyTransition {
        .modifier(active: BlurFade(amount: 1), identity: BlurFade(amount: 0))
    }
}
