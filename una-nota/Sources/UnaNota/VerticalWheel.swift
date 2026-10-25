import AppKit
import DroppyKit
import SwiftUI

// A vertical picker column in the shape of the iOS date picker: the chosen row bright in the
// middle, the rows above and below fading away. Three of them side by side make the date step.

/// Shared look for every column; the curves stay the same across columns.
struct WheelStyle {
    /// Spacing between rows at the centre.
    let pitch: CGFloat
    /// Visible height of the column.
    let height: CGFloat
    /// Strongest blur, at the top and bottom edges.
    let edgeBlur: CGFloat
    /// How far the blur reaches in from each edge.
    let blurBand: CGFloat
    /// Dark fade at the top and bottom.
    var fadeHeight: CGFloat = 30

    /// The date and the time wheels: five rows in view, filling the body.
    static let date = WheelStyle(pitch: 30, height: 190, edgeBlur: 4, blurBand: 72, fadeHeight: 38)
    static let time = date

    func scale(_ distance: CGFloat) -> CGFloat {
        0.88 + 0.12 * Self.bell(distance, width: 1.6)
    }

    func opacity(_ distance: CGFloat) -> Double {
        Double(0.08 + 0.92 * Self.bell(distance, width: 1.15))
    }

    /// Rows gather a little towards the edges.
    func offset(_ t: CGFloat) -> CGFloat {
        let reach = pitch * 6
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
    var pitch: CGFloat = 30
    /// Endless ring when true, a column with ends when false.
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
            let delta = abs(dy) >= abs(dx) ? dy : dx
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

    /// Tapping a far row scrolls there instead of jumping.
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

    /// Scrolls to an item, the short way round a ring.
    func glide(to index: Int) {
        guard wraps else {
            go(to: index)
            return
        }
        let base = Int(position.rounded())
        var delta = index - wrap(base)
        if delta > count / 2 { delta -= count }
        if delta < -count / 2 { delta += count }
        go(to: base + delta)
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

/// One column: the items stacked vertically, the chosen one centred.
struct VerticalWheel<Item: Hashable, Cell: View>: View {
    @ObservedObject var engine: WheelEngine
    let items: [Item]
    @Binding var selection: Item
    let style: WheelStyle
    /// False for a column with ends.
    var wraps = true
    /// 1 hides every row but the centre one, for the collapse into a chip.
    var collapse: CGFloat = 0
    @ViewBuilder let cell: (Item, Bool) -> Cell

    @State private var height: CGFloat = 0

    private static var reach: Int { 5 }

    /// Rows to draw. Blurred copies draw only the rows near their edge.
    private func visibleRows(for copy: EdgeBlurCopy, position: CGFloat) -> [Int] {
        let centre = Int(position.rounded())
        var all = Array((centre - Self.reach)...(centre + Self.reach))
        if !wraps { all = all.filter { $0 >= 0 && $0 < items.count } }
        guard copy.step > 0, height > 0 else { return all }
        let threshold = height / 2 - copy.reach - style.pitch / 2
        return all.filter { abs(style.offset(CGFloat($0) - position)) >= threshold }
    }

    var body: some View {
        let position = engine.position
        ProgressiveEdgeBlur(maxRadius: style.edgeBlur, band: style.blurBand) { copy in
            ZStack {
                ForEach(visibleRows(for: copy, position: position), id: \.self) { virtual in
                    let t = CGFloat(virtual) - position
                    let distance = abs(t)
                    let isCentred = distance < 0.5
                    cell(items[wraps ? engine.wrap(virtual) : virtual], isCentred)
                        .scaleEffect(style.scale(distance))
                        .opacity(style.opacity(distance))
                        .opacity(isCentred ? 1 : 1 - collapse)
                        .offset(y: style.offset(t))
                        .zIndex(-Double(distance))
                        .onTapGesture { engine.go(to: virtual) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { engine.dragChanged($0.translation.height) }
                .onEnded { engine.dragEnded($0.predictedEndTranslation.height) }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active: engine.isHovering = true
            case .ended: engine.isHovering = false
            }
        }
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: style.fadeHeight)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: style.fadeHeight)
            }
        )
        .onAppear {
            configure()
            engine.start()
        }
        .onChange(of: items) { _, _ in configure() }
        .onChange(of: selection) { _, chosen in
            // A change from outside (Today, a clamped day) glides the column there.
            if let index = items.firstIndex(of: chosen), index != engine.index {
                engine.glide(to: index)
            }
        }
        .onDisappear { engine.stop() }
        .frame(height: style.height)
        .clipped()
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
            // A day past the end of a shorter month lands on its last day.
            engine.place(at: items.count - 1)
            selection = items[items.count - 1]
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

/// Blur that grows towards the top and bottom edges.
///
/// Draws the content a few times with rising blur and blends the copies with gradient masks,
/// so the blur changes continuously with the row's position. Only the sharp copy is
/// interactive. Freelancy's horizontal edge blur, turned on its side.
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

    private func radius(_ step: Int) -> CGFloat {
        maxRadius * pow(CGFloat(step) / CGFloat(Self.steps), 1.6)
    }

    /// Shows this copy only in its part of the edge.
    private func weight(_ step: Int) -> some View {
        VStack(spacing: 0) {
            bandGradient(step, mirrored: false).frame(height: band)
            Rectangle().fill(step == 0 ? Color.black : Color.clear)
            bandGradient(step, mirrored: true).frame(height: band)
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
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

/// Which blurred copy is being drawn.
struct EdgeBlurCopy {
    /// 0 is the sharp copy.
    let step: Int
    /// How far in from the edge this copy is visible.
    let reach: CGFloat
}
