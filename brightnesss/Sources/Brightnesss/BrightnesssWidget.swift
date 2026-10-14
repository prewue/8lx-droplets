import AppKit
import DroppyKit
import SwiftUI

struct BrightnesssWidget: View {
    @ObservedObject var droplet: BrightnesssDroplet
    let context: ShelfWidgetContext

    var body: some View {
        ZStack(alignment: .top) {
            if droplet.screen == .welcome, !context.isCompact {
                WelcomeScreen(droplet: droplet)
                    .transition(DroppyTransition.element)
            } else {
                ControlScreen(droplet: droplet, toggles: droplet.toggles, compact: context.isCompact)
                    .transition(DroppyTransition.element)
            }
        }
        .animation(DroppyAnimation.state, value: droplet.screen)
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// The level, read off a dial. A two-finger swipe anywhere here moves it, a
/// pinch opens it, the sun jumps to XDR and back, and a double-click on the
/// figure puts the panel back at 100.
private struct ControlScreen: View {
    @ObservedObject var droplet: BrightnesssDroplet
    /// Observed here too: the discs flip the moment a switch is set.
    @ObservedObject var toggles: SystemToggles
    let compact: Bool

    @StateObject private var engine = DialEngine()
    @State private var pinchStart: Double?

    var body: some View {
        let disc: CGFloat = compact ? 24 : BrightnesssDroplet.navHeight
        VStack(spacing: DroppySpacing.md) {
            HStack(spacing: DroppySpacing.sm) {
                SunButton(droplet: droplet, size: compact ? 22 : 26)
                Button {
                    droplet.setLevel(100)
                } label: {
                    Text(verbatim: droplet.levelText)
                        .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .contentTransition(.numericText(value: droplet.level))
                        .animation(DroppyAnimation.state, value: droplet.level)
                }
                .buttonStyle(.plain)
                .help("Back to 100%")
                .accessibilityLabel("Level \(droplet.levelText)")
                .accessibilityHint("Puts the display back at 100%")
                if !compact {
                    if let xdrBlock = droplet.xdrBlock {
                        Text(verbatim: xdrBlock.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                            .lineLimit(1)
                            .transition(DroppyTransition.element)
                    } else if let badge = droplet.zoneBadge {
                        ZonePill(text: badge, tint: droplet.zoneColor)
                            .id(badge)
                            .transition(DroppyTransition.element)
                    }
                }
                Spacer(minLength: DroppySpacing.md)
                SystemToggleDisc(
                    systemImage: "moon.fill",
                    title: "Night Shift",
                    tint: Color(red: 1, green: 0.62, blue: 0.25),
                    size: disc,
                    isOn: toggles.nightShift,
                    isAvailable: toggles.nightShiftAvailable
                ) { toggles.setNightShift(!toggles.nightShift) }
                SystemToggleDisc(
                    systemImage: "circle.lefthalf.filled",
                    title: "True Tone",
                    tint: Color(red: 1, green: 0.86, blue: 0.62),
                    size: disc,
                    isOn: toggles.trueTone,
                    isAvailable: toggles.trueToneAvailable
                ) { toggles.setTrueTone(!toggles.trueTone) }
                if !compact {
                    Button { droplet.openSettings() } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: disc))
                    .help("Settings")
                    .accessibilityLabel("Settings")
                }
            }
            .animation(DroppyAnimation.state, value: droplet.zoneBadge)
            .animation(DroppyAnimation.state, value: droplet.xdrBlock)
            .frame(height: disc)

            LevelDial(
                engine: engine,
                minimum: BrightnessEngine.minimum,
                maximum: droplet.maximum,
                limit: droplet.effectiveMaximum,
                tint: droplet.zoneColor,
                height: compact ? LevelDial.pairedHeight : LevelDial.soloHeight,
                showsLabels: !compact
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active: engine.isHovering = true
            case .ended: engine.isHovering = false
            }
        }
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.02)
                .onChanged { gesture in
                    if pinchStart == nil { pinchStart = droplet.level }
                    let start = pinchStart ?? droplet.level
                    // Opening the fingers opens the light: a full pinch is a zone.
                    engine.go(to: start + (gesture.magnification - 1) * 100)
                }
                .onEnded { _ in pinchStart = nil }
        )
        .onAppear {
            engine.position = droplet.level
            engine.onChange = { level, settled in
                droplet.setLevel(level)
                if settled { droplet.noteDialSettled() }
            }
        }
        .onChange(of: droplet.level) { _, level in engine.follow(level) }
    }
}

/// The sun: its rays grow with the level, it glows past 100, and a click
/// takes the display into XDR or back out of it.
private struct SunButton: View {
    @ObservedObject var droplet: BrightnesssDroplet
    let size: CGFloat

    @State private var isHovering = false

    var body: some View {
        let xdr = droplet.zone == .xdr
        Button {
            droplet.toggleXDR()
        } label: {
            Image(systemName: droplet.zoneSymbol)
                .font(.system(size: size * 0.62, weight: .semibold))
                .foregroundStyle(droplet.zoneColor)
                .contentTransition(.symbolEffect(.replace))
                .shadow(color: BrightnesssDroplet.xdrColor.opacity(xdr ? 0.8 : 0), radius: xdr ? 4 + CGFloat((droplet.level - 100) / 100) * 6 : 0)
                .frame(width: size, height: size)
                .scaleEffect(isHovering ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .disabled(!droplet.supportsXDR)
        .onHover { isHovering = $0 }
        .animation(DroppyAnimation.hoverScale, value: isHovering)
        .animation(DroppyAnimation.state, value: xdr)
        .help(xdr ? "Leave XDR" : "Go to full XDR")
        .accessibilityLabel(xdr ? "Leave XDR" : "Go to full XDR")
    }
}

/// A glass disc that reads as lit while its switch is on.
private struct SystemToggleDisc: View {
    let systemImage: String
    let title: String
    let tint: Color
    let size: CGFloat
    let isOn: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        if isAvailable {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(isOn ? tint : AdaptiveColors.notchSurfaceSecondaryText)
                    .frame(width: size, height: size)
                    .shadow(color: tint.opacity(isOn ? 0.7 : 0), radius: isOn ? 5 : 0)
            }
            .buttonStyle(DroppyGlassButtonStyle(shape: AnyShape(Circle()), fill: isOn ? .tinted(tint) : .veil))
            .help(isOn ? "\(title), on" : "\(title), off")
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
            .animation(DroppyAnimation.state, value: isOn)
        }
    }
}

/// The zone's word on tinted glass: XDR in orange, Dimmed in red.
private struct ZonePill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, DroppySpacing.md)
            .frame(height: 26)
            .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)), fill: .tinted(tint))
    }
}
