import AppKit
import SwiftUI

/// Every number of the tab lens, tuned on the real tab bar in
/// Tools/LensTuner (which compiles this file and `CategoryTabs.swift`).
struct LensTuning: Equatable, Sendable {
    /// `displacementMap` amount; negative pulls what is behind outward.
    var amount = -16.3
    /// `CASDFGlassDisplacementEffect` height: how far in from the edge it bends.
    var zone = 20.5
    /// `CASDFGlassDisplacementEffect` curvature.
    var curvature = 3.0
    /// Dispersion, percent: red bends that much less than green, blue more.
    var spread = 15.0
    /// How much the lens grows when lifted.
    var liftX = 1.2
    var liftY = 1.6
    /// The shape the bend follows, points wider and taller than the lens.
    var bendWidth = 0.0
    var bendHeight = 0.0
    /// The mask the bent picture is cut to, points wider and taller than the lens.
    var maskWidth = 0.0
    var maskHeight = -2.0
    /// Corner of the bend shape and the mask, as a share of a full capsule.
    var corner = 0.96
    /// Soft edge of the mask, points.
    var feather = 0.0
    /// The mask's shape is taken out of the bend itself (an SDF subtraction)
    /// instead of cutting the picture: nothing inside it is bent, everything
    /// round it is, and `feather` softens the inner edge of that ring.
    var invertMask = false
    /// A guard for the text: a hole cut out of the finished effect over the
    /// middle of the lens, so the edges and the ends can bend hard without
    /// the label under the lens wobbling. It leaves the bend itself alone,
    /// so the edges keep all of it.
    var guardsText = true
    /// How far in from the lens's ends and from its top and bottom the
    /// guard sits, points; a negative `guardInsetY` makes it taller than the
    /// lens, so only its rounded ends show inside it, as arcs.
    var guardInsetX = 27.1
    var guardInsetY = -6.0
    /// The guard's corners, as a share of a full capsule.
    var guardCorner = 1.0
    /// Soft edge of the guard alone, points; the lens's own edge stays sharp.
    var guardSoftness = 2.0
    /// The rim: a thin line round the lens, lit the way UIKit's lifted lens
    /// is (`CASDFKeyFillHighlightEffect`, a key light and a fill light
    /// opposite it): brightest along the top and the bottom, fading towards
    /// the rounded ends. Drawn as a plain line, not that effect: its distance
    /// field trails the lens by a frame, which showed as a second outline
    /// while the lens landed.
    var rimWidth = 1.0
    /// How bright the line is along the top, along the bottom, and at the ends.
    var rimTop = 0.55
    var rimBottom = 0.4
    var rimEnds = 0.08
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
/// The rim follows UIKit's too, lit along the top and the bottom and dim at
/// the ends, as a gradient through a stroked capsule (see `rimTop`).
///
/// Private Core Animation classes, looked up at run time: on a system
/// without one the view draws only the rim, over the glass under it.
final class LensWarpNSView: NSView {
    /// Room around the lens, so the bend near the edge samples real pixels
    /// and nothing at the rim is cut off.
    static let margin: CGFloat = 40

    private struct Channel {
        let backdrop: CALayer
        let field: CALayer
        let element: CALayer
        /// Subtracted from the field when the mask is inverted.
        let hole: CALayer
    }

    private var channels: [Channel] = []
    /// The lens and the room round it: the only part of the view that draws.
    /// It moves with the lens; the view itself covers the whole tab bar and
    /// never moves, so the lens is placed in the same frame as the glass
    /// under it rather than by an animated view frame of its own.
    private let stage = CALayer()
    /// The lens, in the view's coordinates, top-left origin like SwiftUI's.
    private var lens: CGRect = .zero
    /// Holds the three channels, so they combine before the mask cuts them.
    private let group = CALayer()
    private let mask = CALayer()
    private let cut = CALayer()
    /// The text guard, erased from the mask.
    private let guardHole = CALayer()
    /// The rim: a vertical gradient seen through a stroked capsule.
    private let rim = CAGradientLayer()
    private let rimLine = CAShapeLayer()
    private var tuning = LensTuning.standard
    /// The capsule's size at rest, the size the effects start from.
    private var restSize: CGSize = .zero
    /// Whether the lens bends what is under it: only while it is held.
    private var bends = false
    private var laidOut: (bounds: CGRect, lens: CGRect) = (.zero, .zero)
    /// The zone the bend fields were last given, so they are only replaced
    /// when it moves.
    private var appliedZone = -1.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer { CALayer() }

    func update(tuning: LensTuning, restSize: CGSize, bends: Bool, lens: CGRect) {
        if !isBuilt { build() }
        let changed = tuning != self.tuning || restSize != self.restSize || bends != self.bends || lens != self.lens
        self.lens = lens
        let shapeChanged = tuning != self.tuning
        self.tuning = tuning
        self.restSize = restSize
        self.bends = bends
        if shapeChanged { applyShape() }
        if changed { layoutChannels(force: true) }
    }

    override func layout() {
        super.layout()
        if !isBuilt { build() }
        layoutChannels(force: false)
    }

    /// Moving and resizing only re-frames the layers: rebuilding them every
    /// frame of an animation made the lens flicker.
    private func layoutChannels(force: Bool) {
        guard force || bounds != laidOut.bounds || self.lens != laidOut.lens else { return }
        laidOut = (bounds, self.lens)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The stage round the lens, in layer coordinates (bottom-left origin).
        let area = self.lens.insetBy(dx: -Self.margin, dy: -Self.margin)
        stage.frame = CGRect(x: area.minX, y: bounds.height - area.maxY, width: area.width, height: area.height)
        let bounds = stage.bounds
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
        let guardRect = lens.insetBy(dx: tuning.guardInsetX, dy: tuning.guardInsetY)
        guardHole.frame = guardRect.width > 0 && guardRect.height > 0 ? guardRect : .zero
        guardHole.cornerRadius = min(guardRect.width, guardRect.height) / 2 * tuning.guardCorner
        guardHole.isHidden = !tuning.guardsText || guardRect.width <= 0 || guardRect.height <= 0
        for channel in channels {
            channel.backdrop.frame = bounds
            channel.field.frame = bounds
            channel.element.frame = bend
            channel.element.cornerRadius = bend.height / 2 * tuning.corner
            channel.hole.frame = shape
            channel.hole.cornerRadius = shape.height / 2 * tuning.corner
        }
        rim.frame = lens
        rimLine.frame = rim.bounds
        let inset = tuning.rimWidth / 2
        let edge = rim.bounds.insetBy(dx: inset, dy: inset)
        rimLine.path = CGPath(roundedRect: edge, cornerWidth: edge.height / 2, cornerHeight: edge.height / 2, transform: nil)
        rimLine.lineWidth = tuning.rimWidth
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

    private var isBuilt = false

    private func build() {
        guard let root = layer else { return }
        isBuilt = true
        // The rim first: it draws on every system.
        rimLine.fillColor = nil
        rimLine.strokeColor = NSColor.black.cgColor
        rim.mask = rimLine
        // Layer coordinates run up: the top of the lens is at y = 1.
        rim.startPoint = CGPoint(x: 0.5, y: 1)
        rim.endPoint = CGPoint(x: 0.5, y: 0)
        rim.locations = [0, 0.32, 0.68, 1]
        root.addSublayer(stage)
        stage.addSublayer(rim)
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type,
              let fieldClass = NSClassFromString("CASDFLayer") as? CALayer.Type,
              let elementClass = NSClassFromString("CASDFElementLayer") as? CALayer.Type else {
            applyShape()
            return
        }
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
            backdrop.setValue("killtreeLensDispersion", forKey: "groupName")
            backdrop.addSublayer(field)
            backdrop.filters = [bend, keep]
            if index > 0 { backdrop.compositingFilter = "lightenBlendMode" }
            built.append(Channel(backdrop: backdrop, field: field, element: element, hole: hole))
        }
        cut.backgroundColor = NSColor.black.cgColor
        cut.cornerCurve = .continuous
        mask.addSublayer(cut)
        guardHole.backgroundColor = NSColor.black.cgColor
        guardHole.cornerCurve = .continuous
        guardHole.compositingFilter = "destOut"
        mask.addSublayer(guardHole)
        group.mask = mask
        for channel in built { group.addSublayer(channel.backdrop) }
        stage.insertSublayer(group, below: rim)
        channels = built
        applyShape()
        laidOut = (.zero, .zero)
        needsLayout = true
    }

    private func applyShape() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appliedZone = -1
        rim.colors = [tuning.rimTop, tuning.rimEnds, tuning.rimEnds, tuning.rimBottom]
            .map { NSColor(white: 1, alpha: $0).cgColor }
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
        if tuning.guardSoftness > 0.05, let soften = Self.filter("gaussianBlur") {
            soften.setValue(tuning.guardSoftness, forKey: "inputRadius")
            guardHole.filters = [soften]
        } else {
            guardHole.filters = nil
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
        let zone = max(1, lifted > 0 ? tuning.zone * Double(lens.height / lifted) : tuning.zone)
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
        rim.opacity = Float(tuning.rimOpacity)
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

/// The lens refraction in SwiftUI, laid over the whole tab bar and reaching
/// `LensWarpNSView.margin` past it on every side. `lens` is the lens's frame
/// in the bar's own coordinates, animated: every frame of the lens's
/// animation hands the view the same frame the glass under it is drawn at.
struct LensWarp: View, Animatable {
    var lens: CGRect
    var tuning: LensTuning = .standard
    /// The capsule's resting size; the bend scales from it to the lifted size.
    var restSize: CGSize
    /// Bend what is under the lens: only while the pointer holds it.
    var bends: Bool

    nonisolated var animatableData: CGRect.AnimatableData {
        get { lens.animatableData }
        set { lens.animatableData = newValue }
    }

    var body: some View {
        let margin = LensWarpNSView.margin
        LensWarpView(lens: lens.offsetBy(dx: margin, dy: margin), tuning: tuning, restSize: restSize, bends: bends)
            .padding(-margin)
            .allowsHitTesting(false)
    }
}

private struct LensWarpView: NSViewRepresentable {
    let lens: CGRect
    let tuning: LensTuning
    let restSize: CGSize
    let bends: Bool

    func makeNSView(context: Context) -> LensWarpNSView { LensWarpNSView(frame: .zero) }

    func updateNSView(_ view: LensWarpNSView, context: Context) {
        view.update(tuning: tuning, restSize: restSize, bends: bends, lens: lens)
    }
}
