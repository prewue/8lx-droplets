import AppKit
import DroppyKit
import SwiftUI

// Wheel pickers for icons, colours and currencies. They share one engine, style and edge blur.

/// Shared look for every wheel. A new wheel adds a preset; the curves stay shared.
struct WheelStyle {
    /// Spacing between items at the centre.
    let pitch: CGFloat
    /// Height of the tallest cell.
    let height: CGFloat
    /// Strongest blur, at the edges.
    let edgeBlur: CGFloat
    /// How far the blur reaches in from each edge.
    let blurBand: CGFloat
    /// Dark fade at each edge.
    var fadeWidth: CGFloat = 56

    static let icons = WheelStyle(pitch: 56, height: 44, edgeBlur: 4, blurBand: 150)
    static let colors = WheelStyle(pitch: 56, height: 44, edgeBlur: 6, blurBand: 180)
    static let currencies = WheelStyle(pitch: 76, height: 32, edgeBlur: 4, blurBand: 150)

    func scale(_ distance: CGFloat) -> CGFloat {
        0.45 + 0.55 * Self.bell(distance, width: 1.1)
    }

    func opacity(_ distance: CGFloat) -> Double {
        Double(0.2 + 0.8 * Self.bell(distance, width: 1.3))
    }

    /// Items bunch up smoothly towards the edges.
    func offset(_ t: CGFloat) -> CGFloat {
        let reach = pitch * 4.3
        return reach * tanh(t * pitch / reach)
    }

    /// Gaussian falloff: 1 at the centre.
    private static func bell(_ distance: CGFloat, width: CGFloat) -> CGFloat {
        exp(-(distance * distance) / (2 * width * width))
    }
}

@MainActor
final class WheelEngine: ObservableObject {
    @Published var position: CGFloat = 0

    var count = 1
    var pitch: CGFloat = 56
    /// Endless ring when true, a row with ends when false.
    var wraps = true
    var onIndexChange: ((Int) -> Void)?
    var isHovering = false

    private var monitor: Any?
    private var snapTask: Task<Void, Never>?
    private var dragStart: CGFloat?
    private var lastIndex: Int?

    var index: Int {
        let rounded = Int(position.rounded())
        return wraps ? wrap(rounded) : min(max(rounded, 0), count - 1)
    }

    func wrap(_ value: Int) -> Int {
        ((value % count) + count) % count
    }

    /// Keeps a row with ends inside them.
    private func clamped(_ value: CGFloat) -> CGFloat {
        wraps ? value : min(max(value, 0), CGFloat(max(count - 1, 0)))
    }

    /// Lets a drag stretch a little past the ends.
    private func rubberBanded(_ value: CGFloat) -> CGFloat {
        let edge = clamped(value)
        return edge + (value - edge) * 0.3
    }

    func place(at index: Int) {
        guard wraps else {
            position = CGFloat(min(max(index, 0), max(count - 1, 0)))
            lastIndex = self.index
            return
        }
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
            position = clamped(position - delta / pitch)
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
        settle(on: clamped(position.rounded() + CGFloat(delta)))
    }

    /// Tapping a far item scrolls there instead of jumping.
    func go(to virtualIndex: Int) {
        snapTask?.cancel()
        let target = clamped(CGFloat(virtualIndex))
        let distance = abs(target - position)
        guard distance > 1.5 else {
            settle(on: target)
            return
        }
        withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: min(0.3 + 0.09 * Double(distance), 0.75))) {
            position = target
        }
        report(haptic: false)
    }

    func dragChanged(_ translation: CGFloat) {
        if dragStart == nil {
            dragStart = position
            snapTask?.cancel()
        }
        position = rubberBanded((dragStart ?? position) - translation / pitch)
        report(haptic: true)
    }

    func dragEnded(_ predictedTranslation: CGFloat) {
        let start = dragStart ?? position
        dragStart = nil
        settle(on: clamped((start - predictedTranslation / pitch).rounded()))
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
    let style: WheelStyle
    /// False for a row with ends.
    var wraps = true
    @ViewBuilder let cell: (Item, Bool) -> Cell

    @State private var width: CGFloat = 0

    private static var reach: Int { 6 }

    /// Items to draw. Blurred copies draw only the items near their edge.
    private func visibleItems(for copy: EdgeBlurCopy, position: CGFloat) -> [Int] {
        let centre = Int(position.rounded())
        var all = Array((centre - Self.reach)...(centre + Self.reach))
        if !wraps { all = all.filter { $0 >= 0 && $0 < items.count } }
        guard copy.step > 0, width > 0 else { return all }
        let threshold = width / 2 - copy.reach - style.pitch / 2
        return all.filter { abs(style.offset(CGFloat($0) - position)) >= threshold }
    }

    var body: some View {
        let position = engine.position
        ProgressiveEdgeBlur(maxRadius: style.edgeBlur, band: style.blurBand) { copy in
            ZStack {
                ForEach(visibleItems(for: copy, position: position), id: \.self) { virtual in
                    let t = CGFloat(virtual) - position
                    let distance = abs(t)
                    cell(items[wraps ? engine.wrap(virtual) : virtual], distance < 0.5)
                        .scaleEffect(style.scale(distance))
                        .opacity(style.opacity(distance))
                        .offset(x: style.offset(t))
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
                    .frame(width: style.fadeWidth)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: style.fadeWidth)
            }
        )
        .onAppear {
            configure()
            engine.start()
        }
        .onChange(of: items) { _, _ in configure() }
        .onChange(of: wraps) { _, _ in configure() }
        .onDisappear { engine.stop() }
        .frame(height: style.height)
    }

    /// Syncs the engine with the current items and selection.
    private func configure() {
        guard !items.isEmpty else { return }
        engine.count = items.count
        engine.pitch = style.pitch
        engine.wraps = wraps
        if let index = items.firstIndex(of: selection) {
            engine.place(at: index)
        } else {
            engine.place(at: 0)
            selection = items[0]
        }
        let current = items
        engine.onIndexChange = { index in
            guard current.indices.contains(index) else { return }
            let chosen = current[index]
            if chosen != selection {
                withAnimation(DroppyAnimation.segmentedSelection) { selection = chosen }
            }
        }
    }
}

/// Blur that grows towards the left and right edges.
///
/// Draws the content a few times with rising blur and blends the copies with gradient masks.
/// Only the sharp copy is interactive.
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
                        .environment(\.isBlurredCopy, step != 0)
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

    /// Blur radius for each copy.
    private func radius(_ step: Int) -> CGFloat {
        maxRadius * pow(CGFloat(step) / CGFloat(Self.steps), 1.6)
    }

    /// Shows this copy only in its part of the edge.
    private func weight(_ step: Int) -> some View {
        HStack(spacing: 0) {
            bandGradient(step, mirrored: false).frame(width: band)
            Rectangle().fill(step == 0 ? Color.black : Color.clear)
            bandGradient(step, mirrored: true).frame(width: band)
        }
    }

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

/// Which blurred copy is being drawn.
struct EdgeBlurCopy {
    /// 0 is the sharp copy.
    let step: Int
    /// How far in from the edge this copy is visible.
    let reach: CGFloat
}

extension EnvironmentValues {
    /// True inside a blurred copy, so a cell can draw a cheaper version.
    @Entry var isBlurredCopy = false
}

/// Tick-mark ruler for picking a whole number, built on the wheel engine.
struct RulerWheel: View {
    @ObservedObject var engine: WheelEngine
    let range: ClosedRange<Int>
    @Binding var value: Int
    let tint: Color

    static let spacing: CGFloat = 13.5
    static let height: CGFloat = 46
    private static let tickWidth: CGFloat = 3
    private static let restHeight: CGFloat = 24
    private static let edgeBlur: CGFloat = 3
    private static let blurBand: CGFloat = 130
    private static let fadeWidth: CGFloat = 56

    @State private var width: CGFloat = 0

    var body: some View {
        let position = engine.position
        ProgressiveEdgeBlur(maxRadius: Self.edgeBlur, band: Self.blurBand) { copy in
            ZStack {
                ForEach(indices(for: copy, position: position), id: \.self) { index in
                    let distance = abs(CGFloat(index) - position)
                    tick(distance)
                        .offset(x: (CGFloat(index) - position) * Self.spacing)
                        .onTapGesture { engine.go(to: index) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
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
            engine.wraps = false
            engine.count = range.count
            engine.pitch = Self.spacing
            engine.place(at: min(max(value, range.lowerBound), range.upperBound) - range.lowerBound)
            engine.onIndexChange = { index in
                let chosen = range.lowerBound + index
                if chosen != value { value = chosen }
            }
            engine.start()
        }
        .onDisappear { engine.stop() }
        .frame(height: Self.height)
    }

    /// Ticks to draw.
    private func indices(for copy: EdgeBlurCopy, position: CGFloat) -> [Int] {
        let half = Int((max(width, 400) / 2 / Self.spacing).rounded(.up)) + 1
        let centre = Int(position.rounded())
        let all = Array(max(0, centre - half)...min(range.count - 1, centre + half))
        guard copy.step > 0, width > 0 else { return all }
        let threshold = width / 2 - copy.reach - Self.spacing
        return all.filter { abs(CGFloat($0) - position) * Self.spacing >= threshold }
    }

    private func tick(_ distance: CGFloat) -> some View {
        // Only the centre tick is taller.
        let lift = exp(-(distance * distance) / (2 * 0.42 * 0.42))
        // The tint fades out over two ticks either side.
        let fade = distance >= 3 ? 0 : max(0, min(1, (3 - distance) / 0.8))
        let tinted = exp(-0.8 * distance) * fade
        return ZStack {
            Capsule().fill(AdaptiveColors.notchSurfaceCardFill)
            Capsule().fill(tint).opacity(tinted)
        }
        .frame(width: Self.tickWidth, height: Self.restHeight + (Self.height - Self.restHeight) * lift)
    }
}
