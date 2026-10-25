// Archived: the shelf's former menu screen (one glass disc per list, with a
// count badge and the memory under each). Replaced by the tabs in the
// category nav. Not compiled: it lives outside Sources. To bring it back,
// move it into Sources/KillTree, add `case menu` to KillTreeScreen with
// `KillTreeDroplet.menuHeight` (104) in widgetHeight, and route to it from
// KillTreeWidget. It reads `droplet.summary(of:)`, which is still there.

import DroppyKit
import SwiftUI

// MARK: - Menu

/// The menu, like Freelancy's: one glass disc per list.
private struct MenuScreen: View {
    @ObservedObject var droplet: KillTreeDroplet

    var body: some View {
        HStack(alignment: .top, spacing: DroppySpacing.xxl) {
            ForEach(Category.allCases, id: \.self) { category in
                let summary = droplet.summary(of: category)
                MenuItem(
                    systemImage: category.symbol,
                    title: category.title,
                    memory: summary.memory,
                    count: summary.count
                ) { droplet.show(.category(category)) }
            }
            MenuItem(systemImage: "gearshape", title: "Settings", memory: 0, count: 0) {
                droplet.openSettings()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// A glass disc with its symbol and, on its corner, how many processes are
/// behind it; under it the name and the memory those processes hold.
private struct MenuItem: View {
    static let size: CGFloat = 44

    let systemImage: String
    let title: String
    let memory: UInt64
    let count: Int
    let action: () -> Void

    var body: some View {
        VStack(spacing: DroppySpacing.xsm) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: Self.size, height: Self.size)
            }
            .buttonStyle(DroppyGlassButtonStyle(shape: AnyShape(Circle()), fill: .veil))
            .overlay(alignment: .topTrailing) {
                if count > 0 {
                    CountBadge(count: count)
                        .offset(x: 6, y: -4)
                        .transition(DroppyTransition.element)
                }
            }
            .help(count > 0 ? "\(title), \(count) process\(count == 1 ? "" : "es")" : title)
            Text(verbatim: title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            Text(verbatim: memory > 0 ? Bytes.text(memory) : " ")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .contentTransition(.numericText())
        }
        .frame(minWidth: 64)
        .animation(DroppyAnimation.state, value: count)
        .accessibilityElement(children: .combine)
    }
}

/// A count on a red capsule, the way a notification badge sits on an icon.
private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(verbatim: count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .contentTransition(.numericText(value: Double(count)))
            .padding(.horizontal, 4)
            .frame(minWidth: 17, minHeight: 17)
            .background(Capsule(style: .continuous).fill(KillTreeDroplet.closeTint))
    }
}

