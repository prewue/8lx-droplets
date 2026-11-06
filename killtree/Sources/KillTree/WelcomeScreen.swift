import DroppyKit
import Foundation
import SwiftUI

/// Welcome screen shown until the user steps in.
struct WelcomeScreen: View {
    @ObservedObject var droplet: KillTreeDroplet

    var body: some View {
        VStack(spacing: 0) {
            WelcomeEmblem()
                .frame(width: 300, height: 64)

            Text("Welcome to K*llTree")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .padding(.top, DroppySpacing.smd)

            Text("Quitting an app leaves its helpers behind. K*llTree closes the whole family, and can keep it closed.")
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
        ("CoreSync", nil), ("−1.2 GB", nil), ("By 8LX", KillTreeDroplet.closeTint),
        ("KeepAlive", nil), ("Figma Agent", nil), ("AutoUpdate", nil)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let spin = time * 0.45
            ZStack {
                pills(spin: spin, front: false)
                KillTreeLogo(size: Self.logoSize)
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

/// The K*llTree mark on the dark tile, the way the droplet's icon draws it.
struct KillTreeLogo: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.19), Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            KillMark()
                .fill(Color(red: 1, green: 0, blue: 0))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * DroppyRadius.appIconCornerRatio, style: .continuous))
    }
}

/// "K*ll" on its own, without the tile, filling its width.
struct KillWordmark: View {
    let width: CGFloat

    static func height(forWidth width: CGFloat) -> CGFloat {
        width * KillMark.bounds.height / KillMark.bounds.width
    }

    var body: some View {
        KillMark(fillsRect: true)
            .fill(Color(red: 1, green: 0, blue: 0))
            .frame(width: width, height: Self.height(forWidth: width))
    }
}

/// "K*ll" from the droplet's logo, as paths, so it stays sharp at any size and
/// needs no file: the Store replaces the icon document that holds the picture.
private struct KillMark: Shape {
    /// Where the letters sit on the logo's 314-point tile.
    static let bounds = CGRect(x: 36, y: 118, width: 241.386, height: 77.736)
    private static let side: CGFloat = 314
    /// The letters to the edges of the rectangle, rather than placed on a tile.
    var fillsRect = false

    private static let paths = [
        "M60.8347 176.289L60.5653 149.191H62.774L93.4806 118H123.595L88.1474 153.501L79.2048 158.942L60.8347 176.289ZM36 195.736V118H62.1276V195.736H36ZM93.0497 195.736L66.114 161.959L86.0464 147.575L124.78 195.736H93.0497Z",
        "M151.516 118H176.648L174.486 156.913H153.768L151.516 118ZM151.606 195.736L153.858 156.913H174.486L176.738 195.736H151.606ZM121.431 145.834L132.33 125.476L169.171 148.356L159.173 165.38L121.431 145.834ZM206.914 145.834L169.171 165.38L159.173 148.356L196.014 125.476L206.914 145.834ZM206.823 167.903L195.924 188.35L159.083 165.38L169.081 148.356L206.823 167.903ZM121.431 167.903L159.173 148.356L169.261 165.38L132.42 188.26L121.431 167.903Z",
        "M253.277 195.27V118H277.386V195.27H253.277Z",
        "M216 195.27V118H240.108V195.27H216Z"
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for data in Self.paths { Self.add(data, to: &path) }
        let origin = fillsRect ? Self.bounds.origin : .zero
        let scale = fillsRect ? rect.width / Self.bounds.width : min(rect.width, rect.height) / Self.side
        return path.applying(
            CGAffineTransform(translationX: -origin.x, y: -origin.y)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        )
    }

    /// The four commands these paths use: M, L, H, V and Z.
    private static func add(_ data: String, to path: inout Path) {
        let scanner = Scanner(string: data)
        scanner.charactersToBeSkipped = .whitespaces
        var point = CGPoint.zero
        let commands = CharacterSet(charactersIn: "MLHVZ")
        while let command = scanner.scanCharacters(from: commands) {
            for letter in command {
                switch letter {
                case "M", "L":
                    guard let x = scanner.scanDouble(), let y = scanner.scanDouble() else { return }
                    point = CGPoint(x: x, y: y)
                    if letter == "M" { path.move(to: point) } else { path.addLine(to: point) }
                case "H":
                    guard let x = scanner.scanDouble() else { return }
                    point.x = x
                    path.addLine(to: point)
                case "V":
                    guard let y = scanner.scanDouble() else { return }
                    point.y = y
                    path.addLine(to: point)
                default:
                    path.closeSubpath()
                }
            }
        }
    }
}
