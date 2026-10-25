import DroppyKit
import SwiftUI

/// Welcome screen shown until the user steps in.
struct WelcomeScreen: View {
    @ObservedObject var droplet: KillteeDroplet

    var body: some View {
        VStack(spacing: 0) {
            WelcomeEmblem()
                .frame(width: 300, height: 64)

            Text("Welcome to K*llTree")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .padding(.top, DroppySpacing.smd)

            Text("Quitting an app leaves its helpers behind. K*llTree closes the whole family and keeps it closed until you open the app again.")
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 380)
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

/// The mark with pills of what lingers orbiting it, like Brightnesss'.
private struct WelcomeEmblem: View {
    private static let logoSize: CGFloat = 54
    private static let badges: [(text: String, tint: Color?)] = [
        ("CoreSync", nil), ("−1.2 GB", nil), ("By 8LX", KillteeDroplet.closeTint),
        ("KeepAlive", nil), ("Figma Agent", nil), ("AutoUpdate", nil)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spin = time * 0.45
            ZStack {
                pills(spin: spin, front: false)
                KillteeLogo(size: Self.logoSize, pulse: (sin(time * 2) + 1) / 2)
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
                        .offset(x: 112 * cos(angle), y: 14 * depth)
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

/// The K*llTree mark: a cross in a red disc on the dark tile, with a ring
/// that breathes, the way a process tree collapses into one.
struct KillteeLogo: View {
    let size: CGFloat
    var pulse: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.19), Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .strokeBorder(KillteeDroplet.closeTint.opacity(0.25 + 0.2 * pulse), lineWidth: size * 0.025)
                .frame(width: size * (0.66 + 0.06 * pulse), height: size * (0.66 + 0.06 * pulse))

            Circle()
                .fill(LinearGradient(
                    colors: [Color(red: 1, green: 0.5, blue: 0.45), KillteeDroplet.closeTint, Color(red: 0.82, green: 0.18, blue: 0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: size * 0.46, height: size * 0.46)
                .shadow(color: KillteeDroplet.closeTint.opacity(0.5), radius: size * 0.06, y: size * 0.01)

            Image(systemName: "xmark")
                .font(.system(size: size * 0.2, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * DroppyRadius.appIconCornerRatio, style: .continuous))
    }
}
