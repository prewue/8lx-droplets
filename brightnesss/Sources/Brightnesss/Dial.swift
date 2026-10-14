import AppKit
import DroppyKit
import SwiftUI

/// The dial's motion: a position in level units, moved by a two-finger swipe
/// anywhere over the widget, a drag with momentum, a click on a tick, or the
/// level changing elsewhere. Snaps to whole levels, and onto 0 and 100 when
/// it stops near them.
@MainActor
final class DialEngine: ObservableObject {
    @Published var position: Double = 100

    var minimum: Double = -100
    var maximum: Double = 200
    var pitch: CGFloat = 4.5
    var isHovering = false
    /// Every move, with whether the dial has come to rest.
    var onChange: ((Double, Bool) -> Void)?

    private var monitor: Any?
    private var snapTask: Task<Void, Never>?
    private var dragStart: Double?
    private var lastHaptic: Int?
    private var lastZone: BrightnessZone?

    /// True while a finger or the pointer is moving it.
    var isInteracting: Bool { dragStart != nil || snapTask != nil }

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

    /// The level moved elsewhere (a key, a guard): glide there.
    func follow(_ level: Double) {
        guard !isInteracting, abs(position - level) > 0.01 else { return }
        withAnimation(DroppyAnimation.stateEmphasis) { position = level }
        lastZone = zone(of: level)
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    /// A drag stretches a little past the ends.
    private func rubberBanded(_ value: Double) -> Double {
        let edge = clamped(value)
        return edge + (value - edge) * 0.3
    }

    private func scroll(precise: Bool, dx: CGFloat, dy: CGFloat) {
        if precise {
            let delta = abs(dx) >= abs(dy) ? dx : dy
            guard delta != 0 else { return }
            snapTask?.cancel()
            position = clamped(position - Double(delta / pitch))
            report(settled: false)
            scheduleSnap()
        } else {
            let delta = dy != 0 ? dy : dx
            guard delta != 0 else { return }
            step(delta > 0 ? -5 : 5)
        }
    }

    private func scheduleSnap() {
        snapTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled, let self else { return }
            self.snapTask = nil
            self.settle(on: self.position)
        }
    }

    func step(_ delta: Double) {
        snapTask?.cancel()
        snapTask = nil
        settle(on: clamped(position.rounded() + delta))
    }

    /// A click on a far tick glides there instead of jumping.
    func go(to target: Double) {
        snapTask?.cancel()
        snapTask = nil
        let target = clamped(target)
        let distance = abs(target - position)
        guard distance > 1.5 else {
            settle(on: target)
            return
        }
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: min(0.25 + 0.004 * distance, 0.75))) {
            position = target
        }
        report(settled: true)
    }

    func dragChanged(_ translation: CGFloat) {
        if dragStart == nil {
            dragStart = position
            snapTask?.cancel()
            snapTask = nil
        }
        position = rubberBanded((dragStart ?? position) - Double(translation / pitch))
        report(settled: false)
    }

    func dragEnded(_ predictedTranslation: CGFloat) {
        let start = dragStart ?? position
        dragStart = nil
        settle(on: clamped(start - Double(predictedTranslation / pitch)))
    }

    /// Whole levels, and 0 or 100 when within reach of them.
    private func settle(on target: Double) {
        var snapped = target.rounded()
        for magnet in [0.0, 100.0] where abs(target - magnet) < 2.5 { snapped = magnet }
        withAnimation(DroppyAnimation.stateEmphasis) { position = clamped(snapped) }
        report(settled: true)
    }

    private func zone(of level: Double) -> BrightnessZone {
        if level < 0 { return .dim }
        if level > 100 { return .xdr }
        return .normal
    }

    /// A tap every five levels, a firmer one on crossing into another zone.
    private func report(settled: Bool) {
        let level = clamped(position)
        let notch = Int((level / 5).rounded())
        let zone = zone(of: level)
        if !settled {
            if let lastZone, lastZone != zone {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            } else if let lastHaptic, lastHaptic != notch {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        lastHaptic = notch
        lastZone = zone
        onChange?(level, settled)
    }
}

/// The dial: a ruler of levels scrolling under a fixed needle, ticks in the
/// colour of their zone, the ends fading out.
struct LevelDial: View {
    @ObservedObject var engine: DialEngine
    let minimum: Double
    let maximum: Double
    /// Where a guard has closed the dial: ticks past it draw dim.
    let limit: Double
    let tint: Color
    let height: CGFloat
    let showsLabels: Bool

    static let soloHeight: CGFloat = 58
    static let pairedHeight: CGFloat = 40
    private static let pitch: CGFloat = 4.5
    private static let tickWidth: CGFloat = 2
    private static let fadeWidth: CGFloat = 48

    @State private var width: CGFloat = 0

    var body: some View {
        let position = engine.position
        ZStack {
            ZStack(alignment: .top) {
                ForEach(levels(position: position), id: \.self) { level in
                    tick(level, position: position)
                        .offset(x: CGFloat(Double(level) - position) * Self.pitch)
                        .onTapGesture { engine.go(to: Double(level)) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.fadeWidth)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: Self.fadeWidth)
                }
            )
            needle
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { engine.dragChanged($0.translation.width) }
                .onEnded { engine.dragEnded($0.predictedEndTranslation.width) }
        )
        .onAppear {
            engine.minimum = minimum
            engine.maximum = maximum
            engine.pitch = Self.pitch
            engine.start()
        }
        .onChange(of: maximum) { _, value in engine.maximum = value }
        .onDisappear { engine.stop() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brightness level")
        .accessibilityValue("\(Int(position.rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: engine.step(5)
            case .decrement: engine.step(-5)
            @unknown default: break
            }
        }
    }

    /// The fixed mark the ruler reads against, in the zone's colour.
    private var needle: some View {
        VStack(spacing: 0) {
            Capsule(style: .continuous)
                .fill(tint)
                .frame(width: 3, height: tickHeight(major: true) + 6)
                .shadow(color: tint.opacity(0.7), radius: 4)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private func tickHeight(major: Bool) -> CGFloat {
        let rest = showsLabels ? height - 16 : height
        return major ? rest : rest * 0.5
    }

    /// The levels across the width.
    private func levels(position: Double) -> [Int] {
        let half = Int((max(width, 400) / 2 / Self.pitch).rounded(.up)) + 1
        let centre = Int(position.rounded())
        return Array(max(Int(minimum), centre - half)...min(Int(maximum), centre + half))
    }

    private func tick(_ level: Int, position: Double) -> some View {
        let distance = abs(Double(level) - position)
        let major = level % 10 == 0
        let boundary = level == 0 || level == 100
        // Near the needle the ticks brighten, on a bell so nothing pops.
        let near = exp(-(distance * distance) / (2 * 6 * 6))
        let closed = Double(level) > limit
        let color = Self.zoneColor(level)
        return VStack(spacing: 4) {
            Capsule(style: .continuous)
                .fill(color)
                .opacity((boundary ? 0.9 : (major ? 0.55 : 0.28)) * (closed ? 0.35 : 1) + 0.35 * near)
                .frame(width: Self.tickWidth, height: tickHeight(major: major || boundary))
            if showsLabels, level % 25 == 0 {
                Text(verbatim: level < 0 ? "\u{2212}\(-level)" : "\(level)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .fixedSize()
                    .opacity(closed ? 0.4 : 1)
            }
        }
        .frame(width: 30, alignment: .top)
    }

    /// Ticks below 0 are red, the panel's own range plain, XDR orange.
    static func zoneColor(_ level: Int) -> Color {
        if level < 0 { return BrightnesssDroplet.dimColor }
        if level > 100 { return BrightnesssDroplet.xdrColor }
        return AdaptiveColors.notchSurfacePrimaryText
    }
}
