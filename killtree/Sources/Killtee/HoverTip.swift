import AppKit
import DroppyKit
import SwiftUI

// A tooltip of our own, drawn inside the widget. macOS keeps its tooltips
// out of an inactive app's windows, and Droppy is rarely active while the
// shelf is under the pointer, so `.help` never shows there; a separate
// window does not show over the notch's window either. The tip is an
// overlay of the list instead, above its scrolling.
//
// It grows out of the row: the row's own container, holding the text under
// the row, in Droppy's glass over a solid base, with the row drawn again on
// it. The tip takes no clicks: they reach the row under it. With no room
// below, the text goes above instead.

/// A row asking for its tip.
struct TipRequest {
    let text: String
    /// The row's content, drawn again on the container.
    let head: AnyView
    /// Where the row's content is.
    let anchor: Anchor<CGRect>
}

struct TipKey: PreferenceKey {
    static var defaultValue: TipRequest? { nil }

    static func reduce(value: inout TipRequest?, nextValue: () -> TipRequest?) {
        value = value ?? nextValue()
    }
}

private struct TipShownKey: EnvironmentKey {
    static var defaultValue: @MainActor () -> Void { {} }
}

extension EnvironmentValues {
    /// Called as a tip comes up, for the haptic tick.
    var tipShown: @MainActor () -> Void {
        get { self[TipShownKey.self] }
        set { self[TipShownKey.self] = newValue }
    }
}

extension View {
    /// Puts this view, a row's content, at the head of a tip with
    /// `text` once the pointer has rested on the row for a moment.
    /// `isHovering` is the row's own hover state: a second `onHover` on the
    /// same view would never fire.
    func hoverTip(_ text: String, isHovering: Bool) -> some View {
        modifier(HoverTipModifier(text: text, isHovering: isHovering, head: AnyView(self)))
    }

    /// Draws the tips the views inside ask for, over this one.
    func showsHoverTips() -> some View {
        overlayPreferenceValue(TipKey.self) { request in
            GeometryReader { proxy in
                if let request {
                    TipOverlay(text: request.text, head: request.head, headFrame: proxy[request.anchor], area: proxy.size)
                        .id(request.text)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            // Glass and text come up together over the row's own fill, in one
            // soft fade.
            .animation(.easeInOut(duration: 0.28), value: request?.text)
        }
    }
}

private struct HoverTipModifier: ViewModifier {
    let text: String
    let isHovering: Bool
    let head: AnyView

    /// How long the pointer rests before the tip shows.
    private static let delay: Duration = .milliseconds(1100)

    @Environment(\.tipShown) private var tipShown
    @State private var isShown = false
    @State private var wait: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: TipKey.self, value: .bounds) { anchor in
                isShown ? TipRequest(text: text, head: head, anchor: anchor) : nil
            }
            .onChange(of: isHovering) { _, inside in
                wait?.cancel()
                if inside {
                    wait = Task { @MainActor in
                        try? await Task.sleep(for: Self.delay)
                        guard !Task.isCancelled else { return }
                        isShown = true
                        tipShown()
                    }
                } else {
                    isShown = false
                }
            }
            .onDisappear {
                wait?.cancel()
                isShown = false
            }
    }
}

/// The tip over the list: the row's own container, full width along the
/// row and only as wide as the text under it, in Droppy's glass over a
/// solid base, with the row drawn again on it and the text under the row.
private struct TipOverlay: View {
    let text: String
    let head: AnyView
    let headFrame: CGRect
    let area: CGSize

    /// The child row's own container: it reaches `xsm` past the icon on the
    /// left and ends with the row; the row is `processRowHeight` tall.
    private static let lead = DroppySpacing.xsm
    private static let trail = DroppySpacing.sm
    private static let rowHeight = KillteeDroplet.processRowHeight
    private static let textTop: CGFloat = 1
    /// With the line's own descent it reads as the `xsm` on the left.
    private static let textBottom: CGFloat = 3
    static let fontSize: CGFloat = 11
    /// The row's hover fill as it looks over an open block, made solid.
    private static let base = Color(white: 0.215)

    var body: some View {
        let row = CGRect(
            x: headFrame.minX - Self.lead,
            y: headFrame.midY - Self.rowHeight / 2,
            width: headFrame.width + Self.lead,
            height: Self.rowHeight
        )
        let width = row.width - Self.lead - Self.trail
        let text = Self.lines(text, width: width)
        let textSize = Self.measure(text, width: width)
        let extra = Self.textTop + textSize.height + Self.textBottom
        // Under the row, or over it when the widget ends first.
        let below = row.maxY + extra <= area.height
        let panel = CGRect(
            x: row.minX,
            y: below ? row.maxY : row.minY - extra,
            width: min(row.width, textSize.width + Self.lead + Self.trail),
            height: extra
        )
        let shape = TipShape(row: row, panel: panel)
        ZStack(alignment: .topLeading) {
            // Droppy's glass over a solid base of the row's hover shade: the
            // glass bends only the base, so nothing under the tip blurs or
            // leaves reflections in it, and over the row it reads as the
            // row's own fill.
            ZStack {
                shape.fill(Self.base)
                shape
                    .fill(Color.clear)
                    .droppyGlassControlChrome(shape: AnyShape(shape), fill: .veil)
            }
            .compositingGroup()
            head
                .frame(width: headFrame.width, height: headFrame.height, alignment: .leading)
                .offset(x: headFrame.minX, y: headFrame.minY)
            Text(verbatim: text)
                .font(.system(size: Self.fontSize))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: textSize.width, height: textSize.height, alignment: .topLeading)
                .offset(x: headFrame.minX, y: below ? panel.minY + Self.textTop : panel.minY + Self.textBottom)
        }
        .frame(width: area.width, height: area.height, alignment: .topLeading)
    }

    /// The text as it is when it fits on one line; otherwise each sentence
    /// on a line of its own, so no sentence leaves a word or two hanging
    /// on the next line.
    static func lines(_ text: String, width: CGFloat) -> String {
        guard measure(text, width: .greatestFiniteMagnitude).width > width else { return text }
        return text.replacingOccurrences(of: ". ", with: ".\n")
    }

    /// The text's size wrapped to `width`, so the container fits however
    /// many lines it takes.
    static func measure(_ text: String, width: CGFloat) -> CGSize {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: fontSize)]
        )
        return CGSize(width: ceil(rect.width) + 1, height: ceil(rect.height) + 1)
    }
}

/// The row and the text's panel as one outline, left edges flush, rounded
/// outside and softly filled where the narrower panel meets the row.
private struct TipShape: Shape {
    let row: CGRect
    let panel: CGRect

    private static let corner = DroppyRadius.small
    private static let join: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let below = panel.minY >= row.midY
        let top = below ? row : panel
        let bottom = below ? panel : row
        let left = row.minX
        let seam = below ? row.maxY : panel.maxY
        let r = Self.corner
        let points: [(CGPoint, CGFloat)]
        if abs(top.maxX - bottom.maxX) < Self.join * 2 {
            let right = max(top.maxX, bottom.maxX)
            points = [(CGPoint(x: left, y: top.minY), r), (CGPoint(x: right, y: top.minY), r),
                      (CGPoint(x: right, y: bottom.maxY), r), (CGPoint(x: left, y: bottom.maxY), r)]
        } else if bottom.maxX > top.maxX {
            points = [(CGPoint(x: left, y: top.minY), r), (CGPoint(x: top.maxX, y: top.minY), r),
                      (CGPoint(x: top.maxX, y: seam), Self.join), (CGPoint(x: bottom.maxX, y: seam), r),
                      (CGPoint(x: bottom.maxX, y: bottom.maxY), r), (CGPoint(x: left, y: bottom.maxY), r)]
        } else {
            points = [(CGPoint(x: left, y: top.minY), r), (CGPoint(x: top.maxX, y: top.minY), r),
                      (CGPoint(x: top.maxX, y: seam), r), (CGPoint(x: bottom.maxX, y: seam), Self.join),
                      (CGPoint(x: bottom.maxX, y: bottom.maxY), r), (CGPoint(x: left, y: bottom.maxY), r)]
        }
        return Self.rounded(points)
    }

    /// A closed polygon with each corner rounded by its own radius, kept
    /// within half of the sides it joins.
    private static func rounded(_ points: [(CGPoint, CGFloat)]) -> Path {
        var path = Path()
        let count = points.count
        let first = points[0].0, last = points[count - 1].0
        path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for index in 0..<count {
            let (corner, radius) = points[index]
            let previous = points[(index + count - 1) % count].0
            let next = points[(index + 1) % count].0
            let room = min(hypot(corner.x - previous.x, corner.y - previous.y), hypot(next.x - corner.x, next.y - corner.y)) / 2
            path.addArc(tangent1End: corner, tangent2End: next, radius: min(radius, room))
        }
        path.closeSubpath()
        return path
    }
}
