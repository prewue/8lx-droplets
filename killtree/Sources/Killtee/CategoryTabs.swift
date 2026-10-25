import AppKit
import DroppyKit
import SwiftUI

// The nav row and its tabs, apart from the droplet so Tools/LensTuner
// compiles this same file and shows the component exactly as it is.

/// The three lists the widget shows.
public enum Category: String, Sendable, CaseIterable {
    /// Apps and their helpers, by developer.
    case apps
    /// Command-line tools running in a terminal: Claude Code, Codex, a REPL.
    case terminal
    /// Processes serving something on their own: dev servers, Homebrew
    /// services, scripts left running after their terminal closed.
    case servers

    var title: String {
        switch self {
        case .apps: return "Apps"
        case .terminal: return "Terminals"
        case .servers: return "Servers"
        }
    }

    var symbol: String {
        switch self {
        case .apps: return "square.stack.3d.up"
        case .terminal: return "terminal"
        case .servers: return "server.rack"
        }
    }
}

/// Where the refresh button is: at rest, spinning while a scan runs, done
/// once it has really finished.
public enum RefreshPhase: Equatable, Sendable {
    case idle, working, done
}

/// Settings, the three lists as tabs, and a rescan. The tabs stay put
/// while the list under them changes, and one capsule flies to the chosen
/// tab, the way UIKit's segmented control moves its selection.
struct CategoryNavBar: View {
    let selected: Category
    let select: (Category) -> Void
    let openSettings: () -> Void
    let refresh: () -> Void
    var refreshPhase: RefreshPhase = .idle
    var tuning: LensTuning = .standard
    /// Keeps the lens lifted over the chosen tab: the tuner's still view.
    var holdsLifted = false

    nonisolated static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: Self.height))
            .help("Settings")
            .accessibilityLabel("Settings")
            CategoryTabs(selected: selected, select: select, tuning: tuning, holdsLifted: holdsLifted)
            Button(action: refresh) {
                RefreshGlyph(phase: refreshPhase, size: Self.height)
            }
            .buttonStyle(DroppyCircleButtonStyle(size: Self.height))
            .help("Scan again")
            .accessibilityLabel(refreshPhase == .working ? "Scanning" : "Scan again")
        }
        .frame(height: Self.height)
    }
}

/// The three tabs on a glass track, filling the nav between its buttons.
/// The chosen one rests on a light, see-through capsule. It behaves like
/// UIKit's own segmented control (Craft's tabs are one), as recorded at
/// 60 fps:
/// - a click on another tab lifts the capsule into a glass lens, larger than
///   the track, flies it there (about 35 ms up, 200 ms across) and settles it
///   back into the light capsule (about 150 ms);
/// - a press on the chosen tab lifts the lens at once; dragged, it follows
///   the pointer with a little lag and stays lifted while held; let go, it
///   settles on the nearest tab, which becomes the chosen one.
struct CategoryTabs: View {
    let selected: Category
    let select: (Category) -> Void
    var tuning: LensTuning = .standard
    var holdsLifted = false

    @State private var frames: [Category: CGRect] = [:]
    @State private var lensFrame: CGRect = .zero
    @State private var isLifted = false
    @State private var flight = 0
    /// The press in progress: where it started and whether it grabbed the lens.
    @State private var press: (onLens: Bool, grab: CGFloat)?
    /// The tab a drag dropped the lens on: already there, so not flown.
    @State private var landed: Category?
    /// The lens was lifted by a press, so it bends what is under it; a
    /// click flies it clean. Kept until the next flight, so the bend shrinks
    /// away with the settling lens instead of stopping at the release.
    @State private var held = false

    private static let inset: CGFloat = 2
    nonisolated private static let space = "killteeTabs"

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var lifted: Bool { isLifted || holdsLifted }

    /// The lens's frame, grown past the track while it is lifted.
    private var liftedFrame: CGRect {
        guard lifted else { return lensFrame }
        return lensFrame.insetBy(dx: -lensFrame.width * (tuning.liftX - 1) / 2,
                                 dy: -lensFrame.height * (tuning.liftY - 1) / 2)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Category.allCases, id: \.self) { category in
                let isSelected = category == selected
                // The icon and the name, centred in the tab.
                HStack(spacing: DroppySpacing.xs) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text(verbatim: category.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                .padding(.horizontal, DroppySpacing.sm)
                .frame(maxWidth: .infinity)
                .frame(height: CategoryNavBar.height - Self.inset * 2)
                .contentShape(Rectangle())
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.space))
                } action: { frame in
                    frames[category] = frame
                    // Placed, not flown, until the first switch or press.
                    if category == selected, flight == 0, press == nil { lensFrame = frame }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { select(category) }
            }
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity)
        .coordinateSpace(name: Self.space)
        .background(alignment: .topLeading) {
            let frame = liftedFrame
            TabLens(isLifted: lifted, tuning: tuning)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
        }
        // The lens's refraction and rim, over the labels so it bends them
        // too, as large as the lifted lens. The rim is always on the chosen
        // tab; the bend only while the lens is held, growing with it.
        .overlay {
            LensWarp(lens: liftedFrame, tuning: tuning, restSize: lensFrame.size, bends: held || holdsLifted)
        }
        .background {
            let track = Capsule(style: .continuous)
            track
                .fill(AdaptiveColors.notchSurfaceCardFill.opacity(0.35))
                .overlay {
                    track.fill(Color.clear).droppyGlassControlChrome(shape: AnyShape(track), fill: .veil)
                }
        }
        .contentShape(Capsule(style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged(pressChanged)
                .onEnded(pressEnded)
        )
        .onChange(of: selected) { _, target in
            // A drag already carried the lens there; a click flies it.
            if landed == target {
                landed = nil
            } else if press == nil {
                fly(to: target)
            }
        }
    }

    // MARK: Pressing and dragging

    private func pressChanged(_ value: DragGesture.Value) {
        if press == nil {
            let onLens = frames[selected]?.contains(value.startLocation) ?? false
            press = (onLens, value.startLocation.x - lensFrame.midX)
            if onLens, !reducesMotion {
                held = true
                flight += 1
                withAnimation(.spring(response: 0.12, dampingFraction: 0.9)) { isLifted = true }
            }
        }
        guard let press, press.onLens, let first = frames[Category.allCases.first!], let last = frames[Category.allCases.last!] else { return }
        // The lens follows the pointer, a little behind, and keeps to the track.
        let mid = min(max(value.location.x - press.grab, first.midX), last.midX)
        var frame = lensFrame
        frame.origin.x = mid - frame.width / 2
        withAnimation(.interactiveSpring(response: 0.18, dampingFraction: 0.86)) { lensFrame = frame }
    }

    private func pressEnded(_ value: DragGesture.Value) {
        guard let started = press else { return }
        press = nil
        if started.onLens {
            // Settles on the nearest tab, which becomes the chosen one.
            let nearest = Category.allCases.min { a, b in
                abs((frames[a]?.midX ?? 0) - lensFrame.midX) < abs((frames[b]?.midX ?? 0) - lensFrame.midX)
            } ?? selected
            settle(on: nearest)
            if nearest != selected {
                // Chosen once the lens has nearly landed: switching the list
                // under a moving lens cost it frames.
                landed = nearest
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { select(nearest) }
            }
        } else if let tapped = Category.allCases.first(where: { frames[$0]?.contains(value.location) == true }) {
            select(tapped)
        }
    }

    /// Lands a dragged lens: critically damped, so it comes to rest on the
    /// tab without passing it, carrying the speed the drag left it with.
    private func settle(on category: Category) {
        guard let destination = frames[category] else { return }
        flight += 1
        withAnimation(.spring(response: 0.32, dampingFraction: 1)) { lensFrame = destination }
        withAnimation(.spring(response: 0.24, dampingFraction: 1)) { isLifted = false }
    }

    // MARK: Clicking another tab

    private func fly(to target: Category) {
        guard let destination = frames[target] else { return }
        flight += 1
        let current = flight
        guard !reducesMotion else {
            withAnimation(.easeOut(duration: 0.16)) { lensFrame = destination }
            return
        }
        // Lift at once, travel on a soft spring, settle once it is nearly there.
        held = false
        withAnimation(.spring(response: 0.12, dampingFraction: 0.9)) { isLifted = true }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { lensFrame = destination }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // A newer switch, or a press, keeps the lens up.
            guard current == flight, press == nil else { return }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) { isLifted = false }
        }
    }
}

/// The chosen tab's capsule. At rest a light, see-through fill; lifted,
/// Droppy's glass, grown past the track the way UIKit's lens is (the caller
/// sizes it). No shadow: the refraction over it would pull the shadow in as
/// a dark patch. No stroke: `LensWarp` draws the rim.
private struct TabLens: View {
    let isLifted: Bool
    let tuning: LensTuning

    var body: some View {
        let shape = Capsule(style: .continuous)
        ZStack {
            shape
                .fill(Color.white.opacity(0.22))
                .opacity(isLifted ? 0 : 1)
            shape
                .fill(Color.clear)
                .droppyGlassControlChrome(shape: AnyShape(shape), fill: .veil)
                .opacity(isLifted ? 1 : 0)
        }
    }
}

/// The refresh button's glyph. While a scan runs the arrow turns: it
/// speeds up from rest rather than starting at full speed. When the scan has
/// finished it slows to a stop while it melts into a green check on a green
/// tint; a moment later that eases back into the arrow.
private struct RefreshGlyph: View {
    let phase: RefreshPhase
    let size: CGFloat

    /// Degrees a second at full speed, and how long speeding up and slowing
    /// down take.
    private static let speed: Double = 420
    private static let rampUp: Double = 0.3
    private static let rampDown: Double = 0.5

    @State private var startedAt = Date.distantPast
    @State private var stoppedAt: Date?

    var body: some View {
        let isDone = phase == .done
        ZStack {
            Circle()
                .fill(Color.green.opacity(isDone ? 0.22 : 0))
            TimelineView(.animation(paused: !isTurning)) { context in
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(angle(at: context.date)))
            }
            .opacity(isDone ? 0 : 1)
            .scaleEffect(isDone ? 0.7 : 1)
            .blur(radius: isDone ? 3 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.green)
                .opacity(isDone ? 1 : 0)
                .scaleEffect(isDone ? 1 : 0.7)
                .blur(radius: isDone ? 0 : 3)
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: isDone ? 0.5 : 0.6), value: phase)
        .onChange(of: phase) { old, new in
            switch new {
            case .working:
                startedAt = Date()
                stoppedAt = nil
            case .done:
                if old == .working { stoppedAt = Date() }
            case .idle:
                // Back upright for when it fades in again.
                startedAt = .distantPast
                stoppedAt = nil
            }
        }
    }

    /// Turning while a scan runs and while it slows after.
    private var isTurning: Bool {
        phase == .working || (stoppedAt.map { Date().timeIntervalSince($0) < Self.rampDown } ?? false)
    }

    /// Where the arrow points: speeding up evenly from rest, at full speed,
    /// then slowing evenly to a stop once the scan is done.
    private func angle(at date: Date) -> Double {
        guard startedAt != .distantPast else { return 0 }
        func turned(_ t: Double) -> Double {
            let t = max(t, 0)
            if t < Self.rampUp { return Self.speed * t * t / (2 * Self.rampUp) }
            return Self.speed * (t - Self.rampUp / 2)
        }
        guard let stoppedAt else { return turned(date.timeIntervalSince(startedAt)) }
        let atStop = turned(stoppedAt.timeIntervalSince(startedAt))
        let since = min(date.timeIntervalSince(stoppedAt), Self.rampDown)
        let velocity = min(stoppedAt.timeIntervalSince(startedAt) / Self.rampUp, 1) * Self.speed
        return atStop + velocity * since - velocity * since * since / (2 * Self.rampDown)
    }
}
