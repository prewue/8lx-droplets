import DroppyKit
import SwiftUI

/// Welcome screen shown until the user steps in.
struct WelcomeScreen: View {
    @ObservedObject var droplet: BrightnesssDroplet

    var body: some View {
        VStack(spacing: 0) {
            WelcomeEmblem()
                .frame(width: 280, height: 64)

            Text("Welcome to Brightnesss")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .padding(.top, DroppySpacing.smd)

            Text("Push your XDR display past 100% in the sun and dim it below the minimum at night, right from the notch.")
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 340)
                .padding(.top, DroppySpacing.sm)

            Button {
                droplet.finishWelcome()
            } label: {
                Text("Get started")
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

/// The turning sun with pills of what the droplet does orbiting it.
private struct WelcomeEmblem: View {
    private static let logoSize: CGFloat = 54
    private static let badges: [(text: String, tint: Color?)] = [
        ("1600 nits", nil), ("XDR", nil), ("By 8LX", BrightnesssLogo.accent),
        ("Sub-zero", nil), ("Night Shift", nil), ("True Tone", nil)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spin = time * 0.45
            ZStack {
                pills(spin: spin, front: false)
                BrightnesssLogo(size: Self.logoSize, rays: .degrees((time * 12).truncatingRemainder(dividingBy: 360)))
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
                    OrbitPill(text: Self.badges[index].text, tint: Self.badges[index].tint)
                        .scaleEffect(0.72 + 0.28 * (depth + 1) / 2)
                        .opacity(0.35 + 0.65 * (depth + 1) / 2)
                        .offset(x: 104 * cos(angle), y: 14 * depth)
                }
            }
        }
    }
}

private struct OrbitPill: View {
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

/// The Brightnesss mark: a sun on the dark tile, its rays turning.
struct BrightnesssLogo: View {
    let size: CGFloat
    var rays: Angle = .zero

    /// The accent, a warm sun yellow.
    static let accent = Color(red: 1, green: 0.73, blue: 0.2)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.19), Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )

            ForEach(0..<8, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: size * 0.07, height: size * 0.17)
                    .offset(y: -size * 0.37)
                    .rotationEffect(.degrees(Double(index) * 45) + rays)
            }

            Circle()
                .fill(LinearGradient(
                    stops: [
                        .init(color: Color(red: 1, green: 0.86, blue: 0.45), location: 0),
                        .init(color: Self.accent, location: 0.55),
                        .init(color: Color(red: 0.96, green: 0.55, blue: 0.12), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.45), .white.opacity(0.05), .white.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: size * 0.012
                        )
                }
                .frame(width: size * 0.46, height: size * 0.46)
                .shadow(color: Self.accent.opacity(0.45), radius: size * 0.06, y: size * 0.01)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * DroppyRadius.appIconCornerRatio, style: .continuous))
    }
}
