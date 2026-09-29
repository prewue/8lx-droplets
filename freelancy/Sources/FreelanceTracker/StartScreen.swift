import DroppyKit
import SwiftUI

/// Welcome screen shown before the first project.
struct StartScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    /// Where the beam stopped and when it last started, so it resumes smoothly on hover.
    @State private var beamTurns: Double = 0
    @State private var beamRunningSince: Date?

    var body: some View {
        VStack(spacing: 0) {
            StartEmblem()
                .frame(width: 280, height: 64)

            Text("Welcome to Freelancy")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .padding(.top, DroppySpacing.smd)

            Text("Track the hours you give every client and watch what you've earned add up, right beside the notch.")
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.25), location: 0),
                        .init(color: .white, location: 0.5),
                        .init(color: .white.opacity(0.25), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 330)
                .padding(.top, DroppySpacing.sm)

            Button {
                droplet.startNewProject()
            } label: {
                Text("Create project")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, DroppySpacing.xl)
                    .frame(height: 30)
            }
            .buttonStyle(ClearGlassButtonStyle())
            .background { EdgeBeam(turnsBeforePause: beamTurns, runningSince: beamRunningSince) }
            .onHover { hovering in
                if hovering, beamRunningSince == nil {
                    beamRunningSince = Date()
                } else if !hovering, let since = beamRunningSince {
                    beamTurns += Date().timeIntervalSince(since) / EdgeBeam.secondsPerTurn
                    beamRunningSince = nil
                }
            }
            .padding(.top, DroppySpacing.xl)
            // Room for the glow under the button.
            .padding(.bottom, DroppySpacing.mdl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Clear glass on macOS 26 and later, Droppy's glass before that.
private struct ClearGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ClearGlassLabel(configuration: configuration)
    }
}

private struct ClearGlassLabel: View {
    let configuration: ButtonStyleConfiguration

    @State private var isHovering = false

    var body: some View {
        let shape = Capsule(style: .continuous)
        Group {
            if #available(macOS 26.0, *) {
                configuration.label
                    .foregroundStyle(.white)
                    .glassEffect(.clear.interactive(), in: shape)
                    .contentShape(shape)
                    .scaleEffect(configuration.isPressed ? 0.96 : 1)
                    .animation(DroppyAnimation.hoverQuick, value: configuration.isPressed)
            } else {
                configuration.label
                    .foregroundStyle(.white)
                    .droppyGlassControlChrome(
                        shape: AnyShape(shape),
                        isHovering: isHovering,
                        isPressed: configuration.isPressed
                    )
            }
        }
        .onHover { isHovering = $0 }
    }
}

/// Glowing beam that runs around the button's edge on hover.
private struct EdgeBeam: View {
    /// Where the beam stopped and when it started again (nil while paused).
    let turnsBeforePause: Double
    let runningSince: Date?

    static let secondsPerTurn: Double = 2.8
    private static let glowRoom: CGFloat = 24

    private var isActive: Bool { runningSince != nil }

    private static let deepBlue = Color(red: 0, green: 0.35, blue: 1)
    private static let skyBlue = Color(red: 0.35, green: 0.72, blue: 1)

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isActive)) { timeline in
            let turn = turnsBeforePause + (runningSince.map { max(0, timeline.date.timeIntervalSince($0)) / Self.secondsPerTurn } ?? 0)
            let beam = AngularGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.5),
                    .init(color: Self.deepBlue, location: 0.68),
                    .init(color: Self.skyBlue, location: 0.8),
                    .init(color: .white, location: 0.87),
                    .init(color: Self.deepBlue, location: 0.95),
                    .init(color: .clear, location: 1)
                ],
                center: .center,
                angle: .degrees(turn.truncatingRemainder(dividingBy: 1) * 360)
            )
            let shape = Capsule(style: .continuous)
            ZStack {
                // Outer glow that spills past the button.
                shape.fill(beam)
                    .mask(shape.strokeBorder(lineWidth: 10))
                    .blur(radius: 9)
                    .saturation(1.4)
                    // Fade out below the button so the widget edge never cuts it.
                    .padding(Self.glowRoom)
                    .mask {
                        GeometryReader { proxy in
                            let height = proxy.size.height
                            let buttonBottom = height - Self.glowRoom
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: (buttonBottom + 2) / height),
                                    .init(color: .clear, location: (buttonBottom + 12) / height)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }
                    .padding(-Self.glowRoom)

                // Line and inner glow, clipped to the button.
                ZStack {
                    shape.fill(beam)
                        .mask(shape.strokeBorder(lineWidth: 18).blur(radius: 9))
                        .blur(radius: 9)
                        .opacity(0.9)
                    shape.fill(beam)
                        .mask(shape.strokeBorder(lineWidth: 9).blur(radius: 3.5))
                        .blur(radius: 3.5)
                        .blendMode(.plusLighter)
                    shape.fill(beam)
                        .mask(shape.strokeBorder(lineWidth: 2.5))
                        .blendMode(.plusLighter)
                }
                .compositingGroup()
                .saturation(1.35)
                .clipShape(shape)
            }
        }
        .opacity(isActive ? 1 : 0)
        .animation(DroppyAnimation.hover, value: isActive)
        .allowsHitTesting(false)
    }
}

/// Turning logo with earnings pills orbiting it.
private struct StartEmblem: View {
    private static let logoSize: CGFloat = 54
    private static let badges: [(text: String, tint: Color?)] = [
        ("+$124", nil), ("+$81", nil), ("By 8LX", FreelancyLogo.blue),
        ("+$56", nil), ("+$97", nil), ("+$38", nil)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spin = time * 0.45
            ZStack {
                pills(spin: spin, front: false)
                FreelancyLogo(size: Self.logoSize, hand: .degrees((time * 60).truncatingRemainder(dividingBy: 360)))
                pills(spin: spin, front: true)
            }
        }
        .accessibilityHidden(true)
    }

    private func pills(spin: Double, front: Bool) -> some View {
        ZStack {
            ForEach(Self.badges.indices, id: \.self) { index in
                let angle = spin + Double(index) * 2 * .pi / Double(Self.badges.count)
                let depth = sin(angle)
                if (depth >= 0) == front {
                    EarningPill(text: Self.badges[index].text, tint: Self.badges[index].tint)
                        .scaleEffect(0.72 + 0.28 * (depth + 1) / 2)
                        .opacity(0.35 + 0.65 * (depth + 1) / 2)
                        .offset(x: 104 * cos(angle), y: 14 * depth)
                }
            }
        }
    }
}

/// Turning logo without the orbit, for narrow places.
struct TurningLogo: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            FreelancyLogo(size: size, hand: .degrees((time * 60).truncatingRemainder(dividingBy: 360)))
        }
        .accessibilityHidden(true)
    }
}

private struct EarningPill: View {
    let text: String
    var tint: Color?

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint == nil ? AdaptiveColors.notchSurfacePrimaryText : .white)
            .padding(.horizontal, DroppySpacing.sm)
            .frame(height: 20)
            .droppyGlassControlChrome(
                shape: AnyShape(Capsule(style: .continuous)),
                fill: tint.map { .tinted($0) } ?? .veil
            )
            // Solid tint under the glass for a stronger colour.
            .background {
                if let tint {
                    Capsule(style: .continuous).fill(tint.opacity(0.85))
                }
            }
    }
}

/// The Freelancy logo, drawn from the icon's SVG measures so the hand can turn.
struct FreelancyLogo: View {
    let size: CGFloat
    /// Long hand angle; the dots' light follows it.
    var hand: Angle = .zero

    /// Logo blue, #167FFF.
    static let blue = Color(red: 0.086, green: 0.498, blue: 1)

    private static let canvas: CGFloat = 1224
    private static let short = Angle.degrees(131.2)

    var body: some View {
        let unit = size / Self.canvas
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0, green: 0.192, blue: 0.820), location: 0),
                    .init(color: Self.blue, location: 0.5),
                    .init(color: Color(red: 0.651, green: 0.808, blue: 1), location: 0.75),
                    .init(color: .white, location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0, green: 0.220, blue: 0.902).opacity(0.42))
                .frame(width: 840 * unit, height: 840 * unit)
                .blur(radius: 143.7 * unit)

            Circle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.15), location: 0),
                        .init(color: .white.opacity(0.325), location: 0.5),
                        .init(color: .white.opacity(0.64), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 840 * unit, height: 840 * unit)

            Circle()
                .stroke(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.15), location: 0),
                            .init(color: .white.opacity(0.04), location: 0.5),
                            .init(color: .white.opacity(0.4), location: 1)
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    ),
                    lineWidth: 20 * unit
                )
                .frame(width: 820 * unit, height: 820 * unit)

            ForEach(0..<16, id: \.self) { index in
                let angle = Double(index) * 22.5
                Circle()
                    .fill(Color.white)
                    .frame(width: 62 * unit, height: 62 * unit)
                    .opacity(Self.dotBrightness(at: angle - hand.degrees))
                    .offset(
                        x: 300 * unit * CGFloat(sin(angle * .pi / 180)),
                        y: -300 * unit * CGFloat(cos(angle * .pi / 180))
                    )
            }

            Group {
                hand(length: 178.1 * unit, angle: Self.short, unit: unit)
                hand(length: 184.3 * unit, angle: hand, unit: unit)
            }
            .offset(x: -0.85 * unit, y: 11.84 * unit)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }

    private func hand(length: CGFloat, angle: Angle, unit: CGFloat) -> some View {
        let width = 61.46 * unit
        return Capsule()
            .fill(Color.white)
            .frame(width: width, height: length + width)
            .offset(y: -length / 2)
            .rotationEffect(angle)
    }

    /// Dot brightness trailing the hand, as in the icon.
    static func dotBrightness(at degrees: Double) -> Double {
        let a = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        if a <= 8.771 { return 0.9785 + 0.0215 * a / 8.771 }
        if a <= 10.353 { return 1 - 0.88 * (a - 8.771) / (10.353 - 8.771) }
        return 0.12 + 0.8585 * (a - 10.353) / (360 - 10.353)
    }
}
