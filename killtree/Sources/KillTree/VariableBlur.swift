import AppKit
import SwiftUI

/// Progressive blur, the way Craft draws it over its scroll views
/// (`CraftVariableBlurView`): the private Core Animation filter
/// "variableBlur" on a backdrop layer, its radius ramped by a gradient mask,
/// strongest at one edge and nothing at the other.
///
/// Craft and Alcove put the filter on the backdrop inside a system visual
/// effect view and hide the material's other layers. Here the view's own
/// layer is a bare `CABackdropLayer`: there is no material at all, so
/// nothing grey can flash while the view is moved or rebuilt.
///
/// Private API: every step is looked up at run time, and when one is
/// missing the view stays clear, so the scroll falls back to its plain
/// gradient fade.
final class VariableBlurNSView: NSView {
    enum Edge {
        case top, bottom
    }

    var edge: Edge = .bottom {
        didSet { if edge != oldValue { applyFilter() } }
    }

    var maxRadius: CGFloat = 4 {
        didSet { if maxRadius != oldValue { applyFilter() } }
    }

    private var appliedSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return CALayer() }
        let layer = backdropClass.init()
        // Blur what is behind, not a snapshot of the whole window.
        layer.setValue(true, forKey: "enabled")
        return layer
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyFilter()
    }

    override func layout() {
        super.layout()
        if bounds.size != appliedSize { applyFilter() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyFilter()
    }

    private func applyFilter() {
        guard bounds.width > 0, bounds.height > 0,
              let layer, String(describing: type(of: layer)).contains("Backdrop"),
              let filter = Self.makeVariableBlur(),
              let mask = Self.maskImage(height: bounds.height, edge: edge, flipped: isFlipped) else {
            return
        }
        filter.setValue(maxRadius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        layer.filters = [filter]
        // Craft sets the backdrop to the screen's scale; left alone it blurs
        // a reduced copy and the text under it smears.
        layer.setValue(window?.backingScaleFactor ?? 2, forKey: "scale")
        appliedSize = bounds.size
    }

    /// `[CAFilter filterWithType:@"variableBlur"]`, or nil on a system without it.
    private static func makeVariableBlur() -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector),
              let filter = filterClass.perform(selector, with: "variableBlur")?.takeUnretainedValue() as? NSObject else {
            return nil
        }
        return filter
    }

    /// A one-pixel-wide ramp from full radius at the edge to none across the
    /// band, eased at both ends. Craft holds the full radius over half of its
    /// 128-point band; on the shelf's shorter band that reads as a step.
    private static func maskImage(height: CGFloat, edge: Edge, flipped: Bool) -> CGImage? {
        let rows = max(Int(height.rounded(.up)), 2)
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: rows,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return nil }
        // Bitmap rows run bottom-up; whether the strong end lands on the
        // view's top or bottom depends on the edge and on the view's flip.
        let strongAtBitmapTop = (edge == .top) != flipped
        for row in 0..<rows {
            let position = CGFloat(row) / CGFloat(rows - 1)
            let towardStrong = strongAtBitmapTop ? position : 1 - position
            // Smootherstep over the whole band: no hold, no visible step.
            let t = towardStrong
            context.setFillColor(gray: 0, alpha: t * t * t * (t * (t * 6 - 15) + 10))
            context.fill(CGRect(x: 0, y: row, width: 1, height: 1))
        }
        return context.makeImage()
    }
}

/// How the list's edges fade.
struct FadeStyle: Equatable, Sendable {
    /// Height of the gradient fade at an edge, in points.
    var fadeHeight: CGFloat
    /// Height of the progressive blur band, in points.
    var blurHeight: CGFloat
    /// The blur's radius at the very edge.
    var blurRadius: CGFloat
    /// How far the blur runs past the visible edge, so its own edge stays
    /// out of sight.
    var overscan: CGFloat
    var blurEnabled: Bool

    /// Tuned by eye on the real shelf.
    static let standard = FadeStyle(fadeHeight: 35, blurHeight: 65, blurRadius: 4, overscan: 40, blurEnabled: true)
}

/// The progressive blur in SwiftUI. Nothing under Reduce Motion: the scroll
/// keeps only its gradient fade.
struct VariableBlur: NSViewRepresentable {
    let edge: VariableBlurNSView.Edge
    var maxRadius: CGFloat = 4

    func makeNSView(context: Context) -> VariableBlurNSView {
        let view = VariableBlurNSView(frame: .zero)
        view.edge = edge
        view.maxRadius = maxRadius
        return view
    }

    func updateNSView(_ view: VariableBlurNSView, context: Context) {
        view.edge = edge
        view.maxRadius = maxRadius
    }
}
