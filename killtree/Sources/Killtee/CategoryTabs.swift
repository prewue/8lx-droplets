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

/// Settings, the three lists as tabs, and a rescan. The tabs stay put
/// while the list under them changes, and one capsule flies to the chosen
/// tab, the way UIKit's segmented control moves its selection.
struct CategoryNavBar: View {
    let selected: Category
    let select: (Category) -> Void
    let openSettings: () -> Void
    let refresh: () -> Void
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
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: Self.height))
            .help("Scan again")
            .accessibilityLabel("Scan again")
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
        .overlay(alignment: .topLeading) {
            let frame = liftedFrame
            let margin = LensWarpNSView.margin
            LensWarp(tuning: tuning, restSize: lensFrame.size, bends: held || holdsLifted)
                .frame(width: frame.width + margin * 2, height: frame.height + margin * 2)
                .offset(x: frame.minX - margin, y: frame.minY - margin)
                .allowsHitTesting(false)
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
            if nearest != selected {
                landed = nearest
                select(nearest)
            }
            settle(on: nearest)
        } else if let tapped = Category.allCases.first(where: { frames[$0]?.contains(value.location) == true }) {
            select(tapped)
        }
    }

    private func settle(on category: Category) {
        guard let destination = frames[category] else { return }
        flight += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { lensFrame = destination }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.92)) { isLifted = false }
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
