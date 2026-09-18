import DroppyKit
import SwiftUI

struct RollingDigits: View {
    let text: String
    let font: Font
    let color: Color

    init(_ text: String, font: Font, color: Color) {
        self.text = text
        self.font = font
        self.color = color
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, character in
                DigitCell(character: character, font: font)
                    .id(index)
            }
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

private struct DigitCell: View {
    let character: Character
    let font: Font

    var body: some View {
        ZStack {
            Text(verbatim: String(character))
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .id(character)
                .transition(DigitTransition.roll)
        }
        .animation(DroppyAnimation.state, value: character)
    }
}

enum DigitTransition {
    static var roll: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: DigitRollModifier(offset: 7, blur: 3, opacity: 0),
                identity: DigitRollModifier(offset: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: DigitRollModifier(offset: -7, blur: 3, opacity: 0),
                identity: DigitRollModifier(offset: 0, blur: 0, opacity: 1)
            )
        )
    }
}

private struct DigitRollModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}
