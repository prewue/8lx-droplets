import DroppyKit
import SwiftUI

/// What the shelf shows before the first project, in place of the menu: the Freelancy logo, a
/// greeting, two lines on what it does, and one button that starts the project flow.
///
/// While the animation is being chosen, a click on the logo cycles through the candidates
/// (`StartAnimation`) and replays the one it lands on; the caption under the button names it.
struct StartScreen: View {
    @ObservedObject var droplet: FreelanceTrackerDroplet

    @State private var animation: StartAnimation = .cascade
    /// Bumped on every pick, so a one-shot animation plays again.
    @State private var epoch = 0
    @State private var shown = false
    @State private var pointer: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            StartLogoStage(animation: animation, epoch: epoch, pointer: pointer)
                .frame(width: 140, height: 48)
                .contentShape(Rectangle())
                .onTapGesture { pick(animation.next) }
                .cascade(shown, step: 0, when: animation == .cascade)

            Text("Welcome to Freelancy")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .padding(.top, DroppySpacing.smd)
                .cascade(shown, step: 1, when: animation == .cascade)

            Text("Track the hours you give every client and watch what you've earned add up, right beside the notch.")
                .font(.system(size: 13))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: 330)
                .padding(.top, DroppySpacing.xs)
                .cascade(shown, step: 2, when: animation == .cascade)

            Button {
                droplet.startNewProject()
            } label: {
                Text("Create project")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, DroppySpacing.xl)
                    .frame(height: 30)
            }
            .buttonStyle(DroppyGlassButtonStyle())
            .padding(.top, DroppySpacing.md)
            .cascade(shown, step: 3, when: animation == .cascade)

            Text(verbatim: "\(animation.rawValue + 1) of \(StartAnimation.allCases.count) · \(animation.name) · click the logo for the next")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .padding(.top, DroppySpacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location): pointer = location
            case .ended: pointer = nil
            }
        }
        .onAppear { replay() }
    }

    private func pick(_ next: StartAnimation) {
        animation = next
        epoch += 1
        replay()
    }

    private func replay() {
        shown = false
        DispatchQueue.main.async {
            shown = true
        }
    }
}

/// The candidates for the start screen's animation; one stays once it is chosen.
enum StartAnimation: Int, CaseIterable {
    case cascade
    case clockSweep
    case dotWave
    case assemble
    case tiltShine
    case colourOrbit

    var name: String {
        switch self {
        case .cascade: "Cascade"
        case .clockSweep: "Clock sweep"
        case .dotWave: "Dot wave"
        case .assemble: "Assemble"
        case .tiltShine: "Tilt and shine"
        case .colourOrbit: "Colour orbit"
        }
    }

    var next: StartAnimation {
        StartAnimation(rawValue: (rawValue + 1) % Self.allCases.count) ?? .cascade
    }
}

private extension View {
    /// The cascade: each element rises out of a blur a beat after the one above it.
    func cascade(_ shown: Bool, step: Int, when active: Bool) -> some View {
        let hidden = active && !shown
        return self
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? 10 : 0)
            .blur(radius: hidden ? 6 : 0)
            .animation(active ? DroppyAnimation.state.delay(0.09 * Double(step)) : nil, value: shown)
    }
}

/// The logo with the chosen animation applied to it.
private struct StartLogoStage: View {
    let animation: StartAnimation
    let epoch: Int
    let pointer: CGPoint?

    private static let size: CGFloat = 44

    var body: some View {
        switch animation {
        case .cascade:
            FreelancyLogo(size: Self.size)
        case .clockSweep:
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let sweep = (time * 90).truncatingRemainder(dividingBy: 360)
                FreelancyLogo(
                    size: Self.size,
                    minuteHand: .degrees(sweep),
                    dotLevel: { index in
                        // Lit as the hand passes, fading over the next third of a turn.
                        let behind = (sweep - Double(index) * 30 + 360).truncatingRemainder(dividingBy: 360)
                        return 0.35 + 0.65 * exp(-behind / 70)
                    }
                )
            }
        case .dotWave:
            TimelineView(.animation) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                FreelancyLogo(
                    size: Self.size,
                    dotLevel: { index in 0.5 + 0.5 * sin(time * 4 - Double(index) * .pi / 6) },
                    haloGrows: true
                )
            }
        case .assemble:
            AssemblingLogo(size: Self.size)
                .id(epoch)
        case .tiltShine:
            TiltingLogo(size: Self.size, pointer: pointer)
        case .colourOrbit:
            OrbitingLogo(size: Self.size)
        }
    }
}

/// The Freelancy logo, drawn so its parts can move: the blue superellipse, twelve dots with a
/// halo each, and two white hands, one at twelve and one at half past four.
struct FreelancyLogo: View {
    let size: CGFloat
    var hourHand: Angle = .zero
    var minuteHand: Angle = .degrees(130)
    /// How lit each dot is, 0 to 1.
    var dotLevel: (Int) -> Double = { _ in 1 }
    /// How far the dots are out from the centre, 0 to 1.
    var spread: CGFloat = 1
    var dotScale: (Int) -> CGFloat = { _ in 1 }
    var haloGrows = false

    static let blue = Color(.displayP3, red: 0.097, green: 0.251, blue: 0.954)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(Self.blue)

            ForEach(0..<12, id: \.self) { index in
                let angle = Double(index) * .pi / 6
                let level = dotLevel(index)
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.14 + 0.12 * level))
                        .frame(width: size * 0.14, height: size * 0.14)
                        .scaleEffect(haloGrows ? 0.85 + 0.35 * level : 1)
                    Circle()
                        .fill(Color.white.opacity(0.35 + 0.45 * level))
                        .frame(width: size * 0.085, height: size * 0.085)
                }
                .scaleEffect(dotScale(index))
                .offset(
                    x: size * 0.3 * spread * CGFloat(sin(angle)),
                    y: -size * 0.3 * spread * CGFloat(cos(angle))
                )
            }

            hand(length: size * 0.2, angle: hourHand)
            hand(length: size * 0.19, angle: minuteHand)
        }
        .frame(width: size, height: size)
    }

    private func hand(length: CGFloat, angle: Angle) -> some View {
        let width = size * 0.075
        return Capsule()
            .fill(Color.white)
            .frame(width: width, height: length + width)
            .offset(y: -length / 2)
            .rotationEffect(angle)
    }
}

/// Assemble: the dots fly out from the centre one after another and the hands spin into place.
private struct AssemblingLogo: View {
    let size: CGFloat

    @State private var built = false

    var body: some View {
        FreelancyLogo(
            size: size,
            hourHand: built ? .zero : .degrees(-360),
            minuteHand: built ? .degrees(130) : .degrees(-230),
            spread: built ? 1 : 0.1,
            dotScale: { _ in built ? 1 : 0.2 }
        )
        .scaleEffect(built ? 1 : 0.85)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.72).delay(0.1)) { built = true }
        }
    }
}

/// Tilt and shine: the logo leans towards the pointer and a gloss band crosses it every few
/// seconds.
private struct TiltingLogo: View {
    let size: CGFloat
    let pointer: CGPoint?

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = (time / 3.2).truncatingRemainder(dividingBy: 1)
            GeometryReader { proxy in
                let centre = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let dx = pointer.map { ($0.x - centre.x) / 180 } ?? CGFloat(sin(time * 0.8)) * 0.25
                let dy = pointer.map { ($0.y - centre.y) / 90 } ?? CGFloat(cos(time * 0.8)) * 0.25
                FreelancyLogo(size: size)
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.55), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: size * 0.5)
                        .rotationEffect(.degrees(20))
                        .offset(x: size * (phase * 3 - 1.5))
                        .blendMode(.plusLighter)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
                    .rotation3DEffect(.degrees(Double(max(-1, min(1, dx))) * 18), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .rotation3DEffect(.degrees(Double(max(-1, min(1, dy))) * -14), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                    .position(centre)
            }
        }
    }
}

/// Colour orbit: the nine project colours circle the logo on a tilted ring, passing behind and
/// in front of it.
private struct OrbitingLogo: View {
    let size: CGFloat

    private static let colors = ProjectColor.allCases.map(\.color)

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spin = time * 0.7
            ZStack {
                dots(spin: spin, time: time, front: false)
                FreelancyLogo(size: size)
                dots(spin: spin, time: time, front: true)
            }
        }
    }

    private func dots(spin: Double, time: Double, front: Bool) -> some View {
        ZStack {
            ForEach(Self.colors.indices, id: \.self) { index in
                let angle = spin + Double(index) * 2 * .pi / Double(Self.colors.count)
                let depth = sin(angle)
                if (depth >= 0) == front {
                    Circle()
                        .fill(Self.colors[index])
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.65 + 0.35 * (depth + 1) / 2 + 0.1 * sin(time * 3 + Double(index)))
                        .opacity(0.45 + 0.55 * (depth + 1) / 2)
                        .offset(x: 56 * cos(angle), y: 10 * depth)
                }
            }
        }
    }
}
