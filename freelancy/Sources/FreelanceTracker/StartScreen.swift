import DroppyKit
import SwiftUI

/// Welcome screen shown before the first project.
struct StartScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

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
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
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
            .buttonStyle(DroppyGlassButtonStyle())
            .padding(.top, DroppySpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Turning logo with earnings pills orbiting it.
private struct StartEmblem: View {
    private static let logoSize: CGFloat = 54
    private static let badges: [(text: String, tint: Color?)] = [
        ("+$124", nil), ("+$81", nil), ("By 8LX", FreelancyLogo.accent),
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
        let fill: DroppyGlassControl.Fill = tint.map { .tinted($0) } ?? .veil
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(DroppyGlassControl.ink(for: fill))
            .padding(.horizontal, DroppySpacing.sm)
            .frame(height: 20)
            .droppyGlassControlChrome(shape: AnyShape(Capsule(style: .continuous)), fill: fill)
    }
}

/// The Freelancy logo, drawn from the icon's SVG measures so the hand can turn.
struct FreelancyLogo: View {
    let size: CGFloat
    /// Long hand angle; the dots' light follows it.
    var hand: Angle = .zero

    /// The accent, #5B3FFF.
    static let accent = Color(red: 0.357, green: 0.247, blue: 1)

    private static let canvas: CGFloat = 1224
    private static let short = Angle.degrees(131.2)

    var body: some View {
        let unit = size / Self.canvas
        ZStack {
            // The system-dark tile, as the compiled icon draws it.
            LinearGradient(
                colors: [Color(white: 0.19), Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.486, green: 0.392, blue: 1), location: 0),
                        .init(color: Self.accent, location: 0.55),
                        .init(color: Color(red: 0.290, green: 0.176, blue: 0.941), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay {
                    // The glass edge: light at the top, fading round the sides.
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.35), .white.opacity(0.04), .white.opacity(0.12)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 10 * unit
                        )
                }
                .frame(width: 840 * unit, height: 840 * unit)
                .shadow(color: .black.opacity(0.35), radius: 30 * unit, y: 14 * unit)

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
