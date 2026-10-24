import AppKit
import SwiftUI

/// Every number of the tab lens, tuned on the real tab bar in
/// Tools/LensTuner (which compiles this file and `CategoryTabs.swift`).
struct LensTuning: Equatable, Sendable {
    /// `displacementMap` amount; negative pulls what is behind outward.
    var amount = -20.0
    /// `CASDFGlassDisplacementEffect` height: how far in from the edge it bends.
    var zone = 15.0
    /// `CASDFGlassDisplacementEffect` curvature.
    var curvature = 3.0
    /// Dispersion, percent: red bends that much less than green, blue more.
    var spread = 19.0
    /// How much the lens grows when lifted.
    var liftX = 1.2
    var liftY = 1.6
    /// The shape the bend follows, points wider and taller than the lens.
    var bendWidth = 0.0
    var bendHeight = 0.0
    /// The mask the bent picture is cut to, points wider and taller than the lens.
    var maskWidth = 0.0
    var maskHeight = -12.0
    /// Corner of the bend shape and the mask, as a share of a full capsule.
    var corner = 1.0
    /// Soft edge of the mask, points.
    var feather = 0.0
    /// The mask's shape is taken out of the bend itself (an SDF subtraction)
    /// instead of cutting the picture: nothing inside it is bent, everything
    /// round it is, and `feather` softens the inner edge of that ring.
    var invertMask = false
    /// The rim: UIKit's own highlight, a key light and a fill light opposite
    /// it shining on the capsule's edge (`CASDFKeyFillHighlightEffect`, read
    /// off a live `_UILiquidLensView`; these defaults are its values).
    /// Strength of each light.
    var rimAmount = 0.5
    /// Where the key light comes from, degrees; the fill is opposite.
    var rimAngle = 0.0
    /// How far round the edge each light reaches, degrees.
    var rimSpread = 80.0
    /// How thick the lit edge is.
    var rimHeight = 1.0
    var rimCurvature = 0.75
    var rimOpacity = 1.0

    static let standard = LensTuning()
}

/// The tab lens's refraction, with dispersion the way glass does it.
///
/// The bend is UIKit's own lifted-lens refraction, read off a live
/// `_UILiquidLensView`: a backdrop displaced by the capsule's signed distance
/// field (`displacementMap` from a `CASDFLayer` with a
/// `CASDFGlassDisplacementEffect`), which moves what is behind only near the
/// edge and leaves the middle as it is.
///
/// Dispersion is that same bend three times, once per colour channel, each
/// by its own amount: red least, blue most (`spread` either side of green).
/// All three read one shared capture (`groupName`), keep their own channel
/// through an exact colour matrix and are put back together with `lighten`,
/// a per-channel maximum that leaves an unbent pixel exactly as it was. One
/// mask cuts the three together, after they are combined: masked one by one,
/// a soft or half-drawn edge let the red channel through first.
/// Colour therefore appears only where something is bent, along the shapes
/// of the text and icons under the lens, not as a glow painted on the edge.
///
/// The bend is only for a lens the pointer holds (`bends`): a click flies
/// a clean capsule. Held, the bend follows the lens's size frame by frame,
/// nothing at the resting size and all of it at the lifted size, its zone,
/// mask and soft edge shrinking with the lens; at nothing the three channels
/// match and the view shows what is behind it unchanged, so a settling lens
/// never bends more than its size allows. The rim stays on the chosen tab
/// throughout, lifted or not: it is the capsule's glass edge.
///
/// The rim is UIKit's own too: a `CASDFLayer` lit by a key and a fill light
/// (`CASDFKeyFillHighlightEffect`) through UIKit's `vibrantColorMatrix`, so
/// it brightens where the edge turns towards a light and fades where it
/// turns away, rather than an even line round the shape.
///
/// Private Core Animation classes, looked up at run time: on a system
/// without one the view stays clear and the lens is only the glass under it,
/// with a thin line for a rim.
final class LensWarpNSView: NSView {
    /// Room around the lens, so the bend near the edge samples real pixels
    /// and nothing at the rim is cut off. The lens is the bounds inset by it.
    static let margin: CGFloat = 40

    private struct Channel {
        let backdrop: CALayer
        let field: CALayer
        let element: CALayer
        /// Subtracted from the field when the mask is inverted.
        let hole: CALayer
    }

    private var channels: [Channel] = []
    /// Holds the three channels, so they combine before the mask cuts them.
    private let group = CALayer()
    private let mask = CALayer()
    private let cut = CALayer()
    /// The lit rim, or a plain line where the highlight effect is missing.
    private var rim: CALayer?
    private var rimShape: CALayer?
    private let line = CAShapeLayer()
    private var tuning = LensTuning.standard
    /// The capsule's size at rest, the size the effects start from.
    private var restSize: CGSize = .zero
    /// Whether the lens bends what is under it: only while it is held.
    private var bends = false
    private var laidOut: CGRect = .zero
    /// The zone the bend fields were last given, so they are only replaced
    /// when it moves.
    private var appliedZone = -1.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { CALayer() }

    func update(tuning: LensTuning, restSize: CGSize, bends: Bool) {
        if channels.isEmpty { build() }
        let changed = tuning != self.tuning || restSize != self.restSize || bends != self.bends
        let shapeChanged = tuning != self.tuning
        self.tuning = tuning
        self.restSize = restSize
        self.bends = bends
        if shapeChanged { applyShape() }
        if changed { layoutChannels(force: true) }
    }

    override func layout() {
        super.layout()
        if channels.isEmpty { build() }
        layoutChannels(force: false)
    }

    /// Moving and resizing only re-frames the layers: rebuilding them every
    /// frame of an animation made the lens flicker.
    private func layoutChannels(force: Bool) {
        guard force || bounds != laidOut else { return }
        laidOut = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let lens = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let bend = lens.insetBy(dx: -tuning.bendWidth / 2, dy: -tuning.bendHeight / 2)
        let progress = bends ? lift(of: lens.size) : 0
        let maskWidth = tuning.maskWidth * progress
        let maskHeight = tuning.maskHeight * progress
        let shape = lens.insetBy(dx: -maskWidth / 2, dy: -maskHeight / 2)
        // Inverted, the picture shows across the whole lens and the mask's
        // shape is a hole in the bend instead.
        let cut = tuning.invertMask ? lens : shape
        group.frame = bounds
        mask.frame = bounds
        self.cut.frame = cut
        self.cut.cornerRadius = cut.height / 2 * (tuning.invertMask ? 1 : tuning.corner)
        for channel in channels {
            channel.backdrop.frame = bounds
            channel.field.frame = bounds
            channel.element.frame = bend
            channel.element.cornerRadius = bend.height / 2 * tuning.corner
            channel.hole.frame = shape
            channel.hole.cornerRadius = shape.height / 2 * tuning.corner
        }
        rim?.frame = bounds
        rimShape?.frame = lens
        rimShape?.cornerRadius = lens.height / 2
        line.frame = bounds
        let edge = lens.insetBy(dx: 0.4, dy: 0.4)
        line.path = CGPath(roundedRect: edge, cornerWidth: edge.height / 2, cornerHeight: edge.height / 2, transform: nil)
        applyStrength(progress: progress)
        CATransaction.commit()
    }

    /// How far the lens is between its resting and lifted size, 0 to 1.
    private func lift(of lens: CGSize) -> Double {
        guard restSize.height > 0, restSize.width > 0 else { return 1 }
        let byHeight = tuning.liftY - 1, byWidth = tuning.liftX - 1
        let progress = byHeight >= byWidth
            ? (lens.height / restSize.height - 1) / max(byHeight, 0.0001)
            : (lens.width / restSize.width - 1) / max(byWidth, 0.0001)
        return min(max(progress, 0), 1)
    }

    private func build() {
        guard let root = layer,
              let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let fieldClass = NSClassFromString("CASDFLayer") as? CALayer.Type,
              let elementClass = NSClassFromString("CASDFElementLayer") as? CALayer.Type else { return }
        var built: [Channel] = []
        for index in 0..<3 {
            guard let bend = Self.filter("displacementMap"),
                  let keep = Self.filter("colorMatrix") else { return }
            let field = fieldClass.init()
            field.name = "warpSDF"
            let element = elementClass.init()
            element.cornerCurve = .continuous
            field.addSublayer(element)
            let hole = elementClass.init()
            hole.cornerCurve = .continuous
            hole.setValue("subtraction", forKey: "operation")

            bend.setValue("bend", forKey: "name")
            bend.setValue(0.0, forKey: "inputAmount")
            bend.setValue("warpSDF", forKey: "inputSourceSublayerName")
            var matrix = [Float](repeating: 0, count: 20)
            matrix[index * 5 + index] = 1
            matrix[18] = 1
            let value = matrix.withUnsafeBytes {
                NSValue(bytes: $0.baseAddress!, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
            }
            keep.setValue(value, forKey: "inputColorMatrix")

            let backdrop = backdropClass.init()
            backdrop.setValue(true, forKey: "enabled")
            backdrop.setValue("killteeLensDispersion", forKey: "groupName")
            backdrop.addSublayer(field)
            backdrop.filters = [bend, keep]
            if index > 0 { backdrop.compositingFilter = "lightenBlendMode" }
            built.append(Channel(backdrop: backdrop, field: field, element: element, hole: hole))
        }
        cut.backgroundColor = NSColor.black.cgColor
        cut.cornerCurve = .continuous
        mask.addSublayer(cut)
        group.mask = mask
        for channel in built { group.addSublayer(channel.backdrop) }
        root.addSublayer(group)
        if NSClassFromString("CASDFKeyFillHighlightEffect") != nil {
            let rim = fieldClass.init()
            let shape = elementClass.init()
            shape.cornerCurve = .continuous
            rim.addSublayer(shape)
            if let vibrant = Self.filter("vibrantColorMatrix") {
                // UIKit's matrix for the highlight: a touch more saturation.
                var matrix: [Float] = [1.1202, -0.1894, -0.019, 0, 0.1471,
                                       -0.0563, 0.9871, -0.0191, 0, 0.1471,
                                       -0.0563, -0.1893, 1.1574, 0, 0.1471,
                                       0, 0, 0, 1, 0]
                let value = matrix.withUnsafeMutableBytes {
                    NSValue(bytes: $0.baseAddress!, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
                }
                vibrant.setValue(value, forKey: "inputColorMatrix")
                vibrant.setValue(1.2, forKey: "inputClamp")
                rim.filters = [vibrant]
            }
            root.addSublayer(rim)
            self.rim = rim
            rimShape = shape
        } else {
            line.fillColor = nil
            line.strokeColor = NSColor(white: 1, alpha: 0.29).cgColor
            line.lineWidth = 0.8
            root.addSublayer(line)
            rim = line
        }
        channels = built
        applyShape()
        laidOut = .zero
        needsLayout = true
    }

    private func applyShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appliedZone = -1
        if rimShape != nil, let light = Self.make("CASDFKeyFillHighlightEffect") {
            let white = NSColor.white.cgColor
            let spread = tuning.rimSpread * .pi / 180
            let angle = tuning.rimAngle * .pi / 180
            let values: [String: Any] = [
                "keyColor": white, "fillColor": white,
                "keyAngle": angle, "fillAngle": angle + .pi,
                "keySpread": spread, "fillSpread": spread,
                "keyAmount": tuning.rimAmount, "fillAmount": tuning.rimAmount,
                "keyHeight": tuning.rimHeight, "fillHeight": tuning.rimHeight,
                "diffuseHeightScale": 8.0, "diffuseAmountScale": 0.15, "diffuseSpreadScale": 0.65,
                "curvature": tuning.rimCurvature
            ]
            for (key, value) in values { light.setValue(value, forKey: key) }
            rim?.setValue(light, forKey: "effect")
        }
        for channel in channels {
            if tuning.invertMask {
                if channel.hole.superlayer == nil { channel.field.addSublayer(channel.hole) }
            } else {
                channel.hole.removeFromSuperlayer()
            }
        }
        // The mask's soft edge; its radius follows the lens's size.
        if cut.filters == nil, let soften = Self.filter("gaussianBlur") {
            soften.setValue("soften", forKey: "name")
            soften.setValue(0.0, forKey: "inputRadius")
            cut.filters = [soften]
        }
        CATransaction.commit()
    }

    /// Sets the bend, its zone and the rim for the lens's current size.
    /// Called inside `layoutChannels`' transaction, so nothing animates on
    /// its own: the size animation drives them.
    private func applyStrength(progress: Double) {
        let feather = tuning.feather * progress
        // Inverted, the soft edge is the subtraction's (the bend eases off
        // towards the hole); otherwise it is the mask's blur.
        for channel in channels {
            channel.field.setValue(tuning.invertMask ? feather : 0, forKey: "smoothness")
        }
        cut.setValue(tuning.invertMask ? 0 : feather, forKeyPath: "filters.soften.inputRadius")
        let amount = tuning.amount * progress
        let spread = tuning.spread
        // The zone keeps its share of the lens as the lens grows and shrinks.
        let lifted = restSize.height * tuning.liftY
        let zone = max(1, lifted > 0 ? tuning.zone * Double((bounds.height - Self.margin * 2) / lifted) : tuning.zone)
        if abs(zone - appliedZone) > 0.05 {
            appliedZone = zone
            for channel in channels {
                guard let effect = Self.make("CASDFGlassDisplacementEffect") else { continue }
                effect.setValue(zone, forKey: "height")
                effect.setValue(tuning.curvature, forKey: "curvature")
                channel.field.setValue(effect, forKey: "effect")
            }
        }
        for (index, channel) in channels.enumerated() {
            let bend = amount * (1 + (Double(index) - 1) * spread / 100)
            channel.backdrop.setValue(bend, forKeyPath: "filters.bend.inputAmount")
        }
        rim?.opacity = Float(tuning.rimOpacity)
    }

    private static func make(_ name: String) -> NSObject? {
        (NSClassFromString(name) as? NSObject.Type)?.init()
    }

    private static func filter(_ type: String) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return nil }
        return filterClass.perform(selector, with: type)?.takeUnretainedValue() as? NSObject
    }
}

/// The lens refraction in SwiftUI. Give it the lens's frame grown by
/// `LensWarpNSView.margin` on every side.
struct LensWarp: NSViewRepresentable {
    var tuning: LensTuning = .standard
    /// The capsule's resting size; the bend scales from it to the lifted size.
    var restSize: CGSize
    /// Bend what is under the lens: only while the pointer holds it.
    var bends: Bool

    func makeNSView(context: Context) -> LensWarpNSView { LensWarpNSView(frame: .zero) }

    func updateNSView(_ view: LensWarpNSView, context: Context) {
        view.update(tuning: tuning, restSize: restSize, bends: bends)
    }
}
