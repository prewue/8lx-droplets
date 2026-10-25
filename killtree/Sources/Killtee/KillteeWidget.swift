import AppKit
import DroppyKit
import SwiftUI

/// The widget. Solo is the list; paired is the total and the heaviest vendor.
struct KillteeWidget: View {
    @ObservedObject var droplet: KillteeDroplet
    let context: ShelfWidgetContext

    var body: some View {
        ZStack(alignment: .top) {
            if context.isCompact {
                PairedView(droplet: droplet)
            } else {
                switch droplet.screen {
                case .welcome:
                    WelcomeScreen(droplet: droplet)
                        .transition(DroppyTransition.element)
                case .category(let category):
                    CategoryScreen(droplet: droplet, category: category)
                        .transition(DroppyTransition.element)
                }
            }
        }
        .animation(DroppyAnimation.state, value: droplet.screen)
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { if !context.isPreview { droplet.widgetAppeared() } }
        .onDisappear { if !context.isPreview { droplet.widgetDisappeared() } }
    }
}

// MARK: - Category

/// Settings, the three lists as tabs, and a rescan.
private struct CategoryNav: View {
    @ObservedObject var droplet: KillteeDroplet

    var body: some View {
        CategoryNavBar(
            selected: droplet.selectedTab,
            select: droplet.selectTab,
            openSettings: droplet.openSettings,
            refresh: droplet.refreshByHand,
            refreshPhase: droplet.refreshPhase
        )
    }
}

private struct CategoryScreen: View {
    @ObservedObject var droplet: KillteeDroplet
    let category: Category

    var body: some View {
        let rows = droplet.rows(for: category)
        let height = droplet.listHeight(for: category)
        VStack(spacing: DroppySpacing.md) {
            CategoryNav(droplet: droplet)
            Group {
                if rows.isEmpty {
                    EmptyState(scanned: droplet.hasScanned, category: category)
                } else {
                    VerticalFadingScroll {
                        LazyVStack(spacing: KillteeDroplet.rowSpacing) {
                            ForEach(rows) { row in
                                RowView(droplet: droplet, row: row)
                            }
                        }
                    }
                }
            }
            .frame(height: height)
            // Only the list changes with the tab; the nav stays.
            .id(category)
            .transition(DroppyTransition.element)
        }
        .animation(DroppyAnimation.state, value: rows.map(\.id))
        .animation(DroppyAnimation.state, value: droplet.expanded)
        // Over the list, not inside its scrolling, so its edges do not cut a tip.
        .showsHoverTips()
        .environment(\.tipShown) { droplet.tipAppeared() }
    }
}

private struct RowView: View {
    @ObservedObject var droplet: KillteeDroplet
    let row: ListRow

    var body: some View {
        Group {
            switch row {
            case let .section(section, count, _):
                SectionHeader(section: section, count: count)
            case let .group(group, children):
                GroupBlock(droplet: droplet, group: group, children: children)
            case let .closed(closed):
                ClosedRow(droplet: droplet, closed: closed)
            case let .task(task, isOpen):
                TaskBlock(droplet: droplet, task: task, isOpen: isOpen)
            }
        }
        .transition(.evaporate)
    }
}

private struct EmptyState: View {
    let scanned: Bool
    var category: Category = .apps

    private var text: String {
        guard scanned else { return "Looking at what runs…" }
        switch category {
        case .apps: return "No app left anything running in the background"
        case .terminal: return "Nothing runs in a terminal"
        case .servers: return "No server or service is running"
        }
    }

    var body: some View {
        VStack(spacing: DroppySpacing.sm) {
            Image(systemName: scanned ? "checkmark.seal.fill" : "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(scanned ? Color.green.opacity(0.85) : AdaptiveColors.notchSurfaceTertiaryText)
            Text(verbatim: text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SectionHeader: View {
    let section: ListSection
    let count: Int

    var body: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Text(verbatim: section.title)
                .font(.system(size: 11, weight: .semibold))
            Text(verbatim: "\(count)")
                .font(.system(size: 11))
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
        .padding(.leading, DroppySpacing.sm)
        .frame(height: KillteeDroplet.sectionHeaderHeight, alignment: .bottom)
    }
}

// MARK: - Blocks

/// A child row's symbol sits on the group's title line: chevron and gap
/// (18), icon (26), gap (8). The column before it holds the tree.
private let treeColumnWidth: CGFloat = 10 + DroppySpacing.sm + 26 + DroppySpacing.sm
private let childSymbolWidth: CGFloat = 14

/// The tree under an open block's icon: the trunk runs down from the
/// icon's centre and every row's twig bends out of it on a rounded corner.
private struct TreeBranch: View {
    let isFirst: Bool
    let isLast: Bool

    /// The trunk on the icon's centre line.
    private static let trunkX: CGFloat = 10 + DroppySpacing.sm + 13
    /// The twig stops short of the row's symbol.
    private static let twigEnd: CGFloat = treeColumnWidth - DroppySpacing.xsm
    /// The first row's trunk reaches up to just under the icon, across the
    /// header's lower margin and the gap before the children.
    private static let reach: CGFloat = (KillteeDroplet.groupRowHeight - 26) / 2 + KillteeDroplet.blockChildrenGap - 3

    var body: some View {
        TreeBranchShape(isFirst: isFirst, isLast: isLast, trunkX: Self.trunkX, twigEnd: Self.twigEnd, reach: Self.reach, gap: KillteeDroplet.childRowSpacing)
            .stroke(AdaptiveColors.notchSurfaceTertiaryText.opacity(0.315), style: StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .round))
            .frame(width: treeColumnWidth)
            .accessibilityHidden(true)
    }
}

private struct TreeBranchShape: Shape {
    let isFirst: Bool
    let isLast: Bool
    let trunkX: CGFloat
    let twigEnd: CGFloat
    let reach: CGFloat
    /// The space down to the next row, which the trunk crosses.
    let gap: CGFloat

    /// The bend from the trunk into a twig.
    private static let radius: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = trunkX + 0.5
        let mid = rect.midY.rounded() + 0.5
        let r = Self.radius
        let top = isFirst ? rect.minY - reach : rect.minY
        // The trunk, down to the next row, or into the last bend.
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: isLast ? mid - r : rect.maxY + gap))
        // The twig, bending out of the trunk on a quarter circle.
        path.move(to: CGPoint(x: x, y: mid - r))
        path.addQuadCurve(to: CGPoint(x: x + r, y: mid), control: CGPoint(x: x, y: mid))
        path.addLine(to: CGPoint(x: twigEnd, y: mid))
        return path
    }
}

/// The chevron that opens a block: it slides out from the left under the
/// pointer, stays while the block is open, and turns as it opens.
private struct DisclosureChevron: View {
    let isOpen: Bool
    let isRevealed: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            .rotationEffect(.degrees(isOpen ? 90 : 0))
            .frame(width: 10)
            .offset(x: isRevealed ? 0 : -10)
            .opacity(isRevealed ? 1 : 0)
            .blur(radius: isRevealed ? 0 : 2)
            .frame(width: isRevealed ? 10 + DroppySpacing.sm : 0, alignment: .leading)
            .animation(DroppyAnimation.state, value: isRevealed)
            .animation(DroppyAnimation.state, value: isOpen)
    }
}

/// What sits behind a block: Droppy's glass while it is open, the card
/// fill under the pointer, nothing otherwise. Always present, so opening a
/// block never rebuilds its content.
private struct BlockSurface: View {
    let isOpen: Bool
    let isHovering: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
    }

    var body: some View {
        ZStack {
            shape
                .fill(Color.clear)
                .droppyGlassControlChrome(shape: AnyShape(shape), fill: .veil)
                .opacity(isOpen ? 1 : 0)
            shape
                .fill(AdaptiveColors.notchSurfaceCardFill)
                .opacity(!isOpen && isHovering ? 1 : 0)
        }
        .animation(DroppyAnimation.state, value: isOpen)
        .animation(DroppyAnimation.hoverQuick, value: isHovering)
        .allowsHitTesting(false)
    }
}

/// Droppy's glass disc, tinted red, with a red cross: the paired widget's.
private struct CloseDisc: View {
    let size: CGFloat
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(KillteeDroplet.closeTint)
                .frame(width: size, height: size)
        }
        .buttonStyle(DroppyGlassButtonStyle(shape: AnyShape(Circle()), fill: .tinted(KillteeDroplet.closeTint)))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A row's way out. Droppy's red disc; pressed once, it stretches into a
/// red Hold to Kill pill with a grey glass disc beside it to step back;
/// held, it fills from the left and kills once full; then it shows the
/// closing in the same pill. A child row's is smaller and, at rest, a bare
/// cross that shows under the pointer.
private struct KillControls: View {
    let size: CGFloat
    /// A child row's: a bare cross at rest instead of the red disc.
    var isQuiet = false
    /// A quiet one shows only under the pointer, or while it asks.
    var isVisible = true
    let status: String?
    let isConfirming: Bool
    let help: String
    let ask: () -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        let isPill = isConfirming || status != nil
        HStack(spacing: DroppySpacing.xsm) {
            if isConfirming && status == nil {
                Button(action: cancel) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: size * 0.4, weight: .semibold))
                }
                .buttonStyle(DroppyCircleButtonStyle(size: size))
                .help("Keep it running")
                .accessibilityLabel("Keep it running")
                .transition(.scale(scale: 0.4, anchor: .trailing).combined(with: .opacity))
            }
            if isQuiet && !isPill {
                Button(action: ask) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(PlainCrossStyle())
                .help(help)
                .accessibilityLabel(help)
                .transition(.opacity)
            } else {
                KillPill(
                    size: size,
                    mode: status.map { .closing($0) } ?? (isConfirming ? .hold : .disc),
                    help: help,
                    ask: ask,
                    kill: confirm
                )
                .transition(isQuiet ? .scale(scale: 0.5, anchor: .trailing).combined(with: .opacity) : .identity)
            }
        }
        .opacity(isVisible || isPill ? 1 : 0)
        .allowsHitTesting(isVisible || isPill)
        .frame(minWidth: 24, alignment: .trailing)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isConfirming)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: status)
        .animation(.easeOut(duration: 0.15), value: isVisible)
    }
}

/// The red glass control itself, one view through all three states so its
/// shape flows from disc to pill and on to the closing.
private struct KillPill: View {
    enum Mode: Equatable {
        case disc, hold, closing(String)
    }

    let size: CGFloat
    let mode: Mode
    let help: String
    let ask: () -> Void
    let kill: () -> Void

    /// How long Kill has to be held.
    private static let holdTime: Double = 1

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var isHovering = false
    @State private var hold: Task<Void, Never>?

    private var red: Color { KillteeDroplet.closeTint }

    private var label: String? {
        switch mode {
        case .disc: return nil
        case .hold: return "Hold to Kill"
        case .closing(let status): return status
        }
    }

    var body: some View {
        let shape = Capsule(style: .continuous)
        HStack(spacing: size * 0.2) {
            if case .closing = mode {
                ProgressView()
                    .controlSize(.mini)
                    .tint(red)
                    .transition(.opacity)
            } else {
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .transition(.opacity)
            }
            if let label {
                Text(verbatim: label)
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .fixedSize()
                    .contentTransition(.interpolate)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .leading)))
            }
        }
        .foregroundStyle(red)
        .padding(.horizontal, mode == .disc ? 0 : size * 0.42)
        .frame(minWidth: size)
        .frame(height: size)
        // The hold fills the pill from the left.
        .background(alignment: .leading) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(red.opacity(0.32))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .droppyGlassControlChrome(shape: AnyShape(shape), fill: .tinted(red), isHovering: isHovering && mode != .disc, isPressed: isHolding)
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if mode == .hold, !isHolding { begin() }
                }
                .onEnded { _ in
                    if mode == .disc { ask() } else { release() }
                }
        )
        .onChange(of: mode) { _, mode in
            if mode != .hold { release() }
        }
        .help(mode == .hold ? "Hold to kill it" : help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode == .hold ? "Kill" : (label ?? help))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            switch mode {
            case .disc: ask()
            case .hold: kill()
            case .closing: break
            }
        }
    }

    private func begin() {
        isHolding = true
        withAnimation(.linear(duration: Self.holdTime)) { progress = 1 }
        hold = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.holdTime))
            guard !Task.isCancelled else { return }
            hold = nil
            isHolding = false
            kill()
        }
    }

    /// Let go before the pill is full: nothing happens, the fill drains.
    private func release() {
        hold?.cancel()
        hold = nil
        isHolding = false
        withAnimation(.easeOut(duration: 0.28)) { progress = 0 }
    }
}

/// A row that leaves: it blurs, sinks back a little and fades, while the
/// list closes over the space it left.
private struct Evaporate: ViewModifier {
    let amount: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: 6 * amount)
            .scaleEffect(1 - 0.06 * amount)
            .opacity(1 - amount)
    }
}

extension AnyTransition {
    fileprivate static var evaporate: AnyTransition {
        .asymmetric(
            insertion: .opacity,
            removal: .modifier(active: Evaporate(amount: 1), identity: Evaporate(amount: 0))
                .animation(.easeOut(duration: 0.42))
        )
    }
}

/// Shaking the way an app's icon does on the iPhone's Home Screen while it
/// can be deleted: a quick rock of under two degrees, a touch of bob.
private struct Jiggle: ViewModifier {
    let isOn: Bool
    /// Rows do not shake in step.
    var phase: Double = 0

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isOn)) { context in
            let t = context.date.timeIntervalSinceReferenceDate + phase
            content
                .rotationEffect(.degrees(isOn ? 1.8 * sin(t * 2 * .pi / 0.26) : 0))
                .offset(y: isOn ? 0.5 * sin(t * 2 * .pi / 0.21 + 1) : 0)
        }
    }
}

extension View {
    fileprivate func jiggle(_ isOn: Bool, phase: Double = 0) -> some View {
        modifier(Jiggle(isOn: isOn, phase: phase))
    }
}

/// An app or a vendor's services, and its processes under it while open.
/// With its app closed it sits back at half opacity, until it is pointed at
/// or opened. Asked to close, its name turns red, the line under it says
/// what will end, and its icon shakes until Kill or the way back is chosen.
private struct GroupBlock: View {
    @ObservedObject var droplet: KillteeDroplet
    let group: AppGroup
    let children: [ProcessCluster]?

    @State private var isHovering = false

    private var subtitle: String {
        if group.isHost { return "Runs K*llTree" }
        let background = group.backgroundProcesses.count
        if background > 0 { return "\(background) in the background" }
        let count = group.processes.count
        return "\(count) process\(count == 1 ? "" : "es")"
    }

    var body: some View {
        let isOpen = children != nil
        let target = ConfirmTarget.group(group.id)
        let isConfirming = droplet.confirming == target
        VStack(spacing: 0) {
            HStack(spacing: DroppySpacing.sm) {
                Button {
                    if isConfirming { droplet.cancelConfirmation() } else { droplet.toggleExpanded(group.id) }
                } label: {
                    HStack(spacing: 0) {
                        DisclosureChevron(isOpen: isOpen, isRevealed: group.isExpandable && (isOpen || isHovering))
                        AppIcon(path: group.iconPath, size: 26)
                            .jiggle(isConfirming)
                            .padding(.trailing, DroppySpacing.sm)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: group.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isConfirming ? KillteeDroplet.closeTint : AdaptiveColors.notchSurfacePrimaryText)
                                .lineLimit(1)
                            Text(verbatim: isConfirming ? droplet.killNote(for: target) : subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                                .lineLimit(1)
                                .contentTransition(.interpolate)
                        }
                        Spacer(minLength: DroppySpacing.sm)
                        if !isConfirming {
                            Text(verbatim: Bytes.text(group.memory))
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                                .contentTransition(.numericText())
                                .transition(.opacity)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.name), \(isConfirming ? droplet.killNote(for: target) : subtitle)")
                .accessibilityHint(isConfirming ? "Keeps it running" : (isOpen ? "Hides its processes" : "Shows its processes"))

                if group.isHost {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .frame(width: 24, height: 24)
                } else {
                    KillControls(
                        size: 24,
                        status: droplet.working[group.id],
                        isConfirming: isConfirming,
                        help: "Close \(group.name) completely",
                        ask: { droplet.requestClose(target) },
                        confirm: { droplet.confirmClose() },
                        cancel: { droplet.cancelConfirmation() }
                    )
                }
            }
            .frame(height: KillteeDroplet.groupRowHeight)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isConfirming)

            if let children {
                VStack(spacing: KillteeDroplet.childRowSpacing) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, cluster in
                        let child = ConfirmTarget.cluster(group: group.id, cluster: cluster.id)
                        ClusterRow(
                            cluster: cluster,
                            isFirst: index == 0,
                            isLast: index == children.count - 1,
                            status: droplet.working["\(group.id)#\(cluster.id)"],
                            isConfirming: droplet.confirming == child,
                            canClose: !(group.isHost || cluster.first.kind == .system || cluster.first.isPrivileged),
                            ask: { droplet.requestClose(child) },
                            confirm: { droplet.confirmClose() },
                            cancel: { droplet.cancelConfirmation() }
                        )
                        .transition(.evaporate)
                    }
                }
                .padding(.top, KillteeDroplet.blockChildrenGap)
                .padding(.bottom, KillteeDroplet.blockBottomInset)
                .transition(DroppyTransition.element)
            }
        }
        .padding(.horizontal, DroppySpacing.sm)
        .background { BlockSurface(isOpen: isOpen, isHovering: isHovering) }
        .opacity(isOpen || group.isAppRunning || isHovering || isConfirming ? 1 : KillteeDroplet.closedAppOpacity)
        .onHover { isHovering = $0 }
        .animation(DroppyAnimation.hoverQuick, value: isHovering)
    }
}

/// One process of an app group, or the same one several times.
private struct ClusterRow: View {
    let cluster: ProcessCluster
    var isFirst = false
    var isLast = false
    let status: String?
    let isConfirming: Bool
    let canClose: Bool
    let ask: () -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    @State private var isHovering = false

    private var symbol: String {
        let process = cluster.first
        if process.isPrivileged { return "lock.fill" }
        if process.isMenuBar { return "menubar.rectangle" }
        switch process.kind {
        case .app: return "macwindow"
        case .bundled: return "square.stack.3d.up"
        case .agent: return process.keepAlive ? "arrow.clockwise" : "gearshape"
        case .helper: return "gearshape.2"
        case .system: return "lock"
        }
    }

    private var tags: [String] {
        let process = cluster.first
        var tags: [String] = []
        if process.isPrivileged { tags.append("Admin") }
        if process.kind == .system { tags.append("System") }
        if process.keepAlive { tags.append("Restarts") }
        if cluster.confidence == .low { tags.append("Unsure") }
        return tags
    }

    /// The icon and the name.
    private var head: some View {
        let process = cluster.first
        return HStack(spacing: DroppySpacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(process.keepAlive ? KillteeDroplet.closeTint : AdaptiveColors.notchSurfaceTertiaryText)
                .frame(width: childSymbolWidth, alignment: .leading)
                .jiggle(isConfirming)
            Text(verbatim: process.name)
                .font(.system(size: 12))
                .foregroundStyle(isConfirming
                    ? KillteeDroplet.closeTint
                    : (process.kind.isBackground ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    var body: some View {
        let process = cluster.first
        HStack(spacing: 0) {
            TreeBranch(isFirst: isFirst, isLast: isLast)
            HStack(spacing: DroppySpacing.sm) {
                head
                if cluster.count > 1 {
                    Text(verbatim: "×\(cluster.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                }
                ForEach(tags, id: \.self) { Tag(text: $0) }
                Spacer(minLength: DroppySpacing.sm)
                if !isConfirming {
                    Text(verbatim: Bytes.text(cluster.memory))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .transition(.opacity)
                }
                if canClose {
                    KillControls(
                        size: 20,
                        isQuiet: true,
                        isVisible: isHovering,
                        status: status,
                        isConfirming: isConfirming,
                        help: "End \(process.name)",
                        ask: ask,
                        confirm: confirm,
                        cancel: cancel
                    )
                } else {
                    Color.clear.frame(width: 24, height: 20)
                }
            }
            .frame(height: KillteeDroplet.processRowHeight)
            .hoverTip(cluster.role, isHovering: isHovering && !isConfirming)
            .background { ChildRowSurface(isHovering: isHovering) }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isConfirming)
        }
        .frame(height: KillteeDroplet.processRowHeight)
    }
}

/// A bare cross that takes a faint light disc under the pointer, and a
/// slightly brighter one while pressed.
private struct PlainCrossStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlainCross(configuration: configuration)
    }

    private struct PlainCross: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .frame(width: 20, height: 20)
                .background {
                    Circle().fill(AdaptiveColors.notchSurfacePrimaryText.opacity(configuration.isPressed ? 0.24 : (isHovering ? 0.15 : 0)))
                }
                .contentShape(Circle())
                .onHover { isHovering = $0 }
                .animation(DroppyAnimation.hoverQuick, value: isHovering)
                .animation(DroppyAnimation.hoverQuick, value: configuration.isPressed)
        }
    }
}

/// A child row's own container: nothing at rest, a faint fill under the
/// pointer. Drawn behind the row, a little past its symbol and close disc,
/// so nothing in the row moves.
private struct ChildRowSurface: View {
    let isHovering: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
            .fill(AdaptiveColors.notchSurfacePrimaryText.opacity(isHovering ? 0.12 : 0))
            .padding(.leading, -DroppySpacing.xsm)
            .animation(DroppyAnimation.hoverQuick, value: isHovering)
            .allowsHitTesting(false)
    }
}

/// A terminal tool and its sessions, or a server and its processes.
private struct TaskBlock: View {
    @ObservedObject var droplet: KillteeDroplet
    let task: TaskGroup
    let isOpen: Bool

    @State private var isHovering = false

    var body: some View {
        let target = ConfirmTarget.task(task.id)
        let isConfirming = droplet.confirming == target
        VStack(spacing: 0) {
            HStack(spacing: DroppySpacing.sm) {
                Button {
                    if isConfirming { droplet.cancelConfirmation() } else { droplet.toggleExpanded(task.id) }
                } label: {
                    HStack(spacing: 0) {
                        DisclosureChevron(isOpen: isOpen, isRevealed: task.isExpandable && (isOpen || isHovering))
                        Image(systemName: task.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                            .frame(width: 26, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 26 * DroppyRadius.appIconCornerRatio, style: .continuous)
                                    .fill(AdaptiveColors.notchSurfaceCardFill)
                            )
                            .jiggle(isConfirming)
                            .padding(.trailing, DroppySpacing.sm)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.xs) {
                                Text(verbatim: task.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(isConfirming ? KillteeDroplet.closeTint : AdaptiveColors.notchSurfacePrimaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let age = task.age, !isConfirming {
                                    Text(verbatim: age)
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                                }
                            }
                            HStack(spacing: DroppySpacing.xsm) {
                                Text(verbatim: isConfirming ? droplet.killNote(for: target) : task.subtitle)
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                                    .lineLimit(1)
                                    .contentTransition(.interpolate)
                                if !isConfirming {
                                    ForEach(task.badges, id: \.self) { Tag(text: $0) }
                                }
                            }
                        }
                        Spacer(minLength: DroppySpacing.sm)
                        if !isConfirming {
                            Text(verbatim: Bytes.text(task.memory))
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                                .contentTransition(.numericText())
                                .transition(.opacity)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(task.name), \(isConfirming ? droplet.killNote(for: target) : task.subtitle)")

                KillControls(
                    size: 24,
                    status: droplet.working[task.id],
                    isConfirming: isConfirming,
                    help: task.category == .terminal ? "End every \(task.name) session" : "Stop \(task.name)",
                    ask: { droplet.requestClose(target) },
                    confirm: { droplet.confirmClose() },
                    cancel: { droplet.cancelConfirmation() }
                )
            }
            .frame(height: KillteeDroplet.groupRowHeight)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isConfirming)

            if isOpen {
                VStack(spacing: KillteeDroplet.childRowSpacing) {
                    ForEach(Array(task.items.enumerated()), id: \.element.id) { index, item in
                        let child = ConfirmTarget.item(task: task.id, item: item.id)
                        TaskItemRow(
                            item: item,
                            role: task.role(of: item),
                            isFirst: index == 0,
                            isLast: index == task.items.count - 1,
                            status: droplet.working[item.id],
                            isConfirming: droplet.confirming == child,
                            ask: { droplet.requestClose(child) },
                            confirm: { droplet.confirmClose() },
                            cancel: { droplet.cancelConfirmation() }
                        )
                        .transition(.evaporate)
                    }
                }
                .padding(.top, KillteeDroplet.blockChildrenGap)
                .padding(.bottom, KillteeDroplet.blockBottomInset)
                .transition(DroppyTransition.element)
            }
        }
        .padding(.horizontal, DroppySpacing.sm)
        .background { BlockSurface(isOpen: isOpen, isHovering: isHovering) }
        .onHover { isHovering = $0 }
        .animation(DroppyAnimation.hoverQuick, value: isHovering)
    }
}

/// One session of a tool, or one kind of process of a server.
private struct TaskItemRow: View {
    let item: TaskItem
    /// What the row is, in a line: its tooltip.
    let role: String
    var isFirst = false
    var isLast = false
    let status: String?
    let isConfirming: Bool
    let ask: () -> Void
    let confirm: () -> Void
    let cancel: () -> Void

    @State private var isHovering = false

    /// The icon and the title.
    private var head: some View {
        HStack(spacing: DroppySpacing.sm) {
            Image(systemName: item.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .frame(width: childSymbolWidth, alignment: .leading)
                .jiggle(isConfirming)
            Text(verbatim: item.title)
                .font(.system(size: 12))
                .foregroundStyle(isConfirming ? KillteeDroplet.closeTint : AdaptiveColors.notchSurfacePrimaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            TreeBranch(isFirst: isFirst, isLast: isLast)
            HStack(spacing: DroppySpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.xsm) {
                    head
                    if !item.detail.isEmpty {
                        Text(verbatim: item.detail)
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    }
                    if let age = item.age {
                        Text(verbatim: age)
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    }
                }
                Spacer(minLength: DroppySpacing.sm)
                if !isConfirming {
                    Text(verbatim: Bytes.text(item.memory))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .transition(.opacity)
                }
                KillControls(
                    size: 20,
                    isQuiet: true,
                    isVisible: isHovering,
                    status: status,
                    isConfirming: isConfirming,
                    help: "End \(item.title)",
                    ask: ask,
                    confirm: confirm,
                    cancel: cancel
                )
            }
            .frame(height: KillteeDroplet.processRowHeight)
            .hoverTip(role, isHovering: isHovering && !isConfirming)
            .background { ChildRowSurface(isHovering: isHovering) }
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isConfirming)
        }
        .frame(height: KillteeDroplet.processRowHeight)
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            .padding(.horizontal, DroppySpacing.xsm)
            .frame(height: 16)
            .background(Capsule(style: .continuous).fill(AdaptiveColors.notchSurfaceCardFill))
    }
}

/// A vendor or a service K*llTree keeps closed, with the way back.
private struct ClosedRow: View {
    @ObservedObject var droplet: KillteeDroplet
    let closed: ClosedGroup

    var body: some View {
        let ago = RelativeDateTimeFormatter().localizedString(for: closed.closedAt, relativeTo: Date())
        HStack(spacing: 0) {
            AppIcon(path: closed.iconPath, size: 26)
                .saturation(0)
                .opacity(0.7)
                .padding(.trailing, DroppySpacing.sm)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: closed.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(1)
                Text(verbatim: "Closed \(ago)")
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: DroppySpacing.sm)
            Button { droplet.restore(closed.id) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, DroppySpacing.smd)
                    .frame(height: 24)
            }
            .buttonStyle(DroppyGlassButtonStyle())
            .help("Let it start again")
        }
        .padding(.horizontal, DroppySpacing.sm)
        .frame(height: KillteeDroplet.groupRowHeight)
    }
}

private struct PairedView: View {
    @ObservedObject var droplet: KillteeDroplet

    var body: some View {
        let top = droplet.visibleGroups.first
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KillteeDroplet.closeTint)
                Text("K*llTree")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }
            Text(verbatim: Bytes.text(droplet.backgroundMemory))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .contentTransition(.numericText())
            Text(verbatim: droplet.visibleGroups.isEmpty ? "Nothing in the background" : "\(droplet.visibleGroups.count) app\(droplet.visibleGroups.count == 1 ? "" : "s") in the background")
                .font(.system(size: 11))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let top {
                HStack(spacing: DroppySpacing.sm) {
                    AppIcon(path: top.iconPath, size: 20)
                    Text(verbatim: top.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if droplet.working[top.id] != nil {
                        ProgressView().controlSize(.mini)
                    } else {
                        CloseDisc(size: 22, help: "Close \(top.name) completely") { droplet.close(top.id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(DroppyAnimation.state, value: droplet.backgroundMemory)
    }
}

// MARK: - Pieces

/// An app's own icon from Finder, or a gear when there is no bundle.
struct AppIcon: View {
    let path: String?
    let size: CGFloat

    var body: some View {
        if let image = IconCache.icon(for: path) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * DroppyRadius.appIconCornerRatio, style: .continuous)
                        .fill(AdaptiveColors.notchSurfaceCardFill)
                )
        }
    }
}

@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for path: String?) -> NSImage? {
        guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
        if let icon = icons[path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }
}

private struct ScrollExtent: Equatable {
    let offset: CGFloat
    let length: CGFloat
}

/// A vertical scroll that fades whichever edge has more behind it, from
/// Freelancy.
struct VerticalFadingScroll<Content: View>: View {
    var style: FadeStyle = .standard
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fadesTop = offset > 1
        let fadesBottom = contentHeight - viewportHeight - offset > 1
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .onGeometryChange(for: ScrollExtent.self) { proxy in
                    ScrollExtent(offset: -proxy.frame(in: .named(verticalFadingScrollSpace)).minY, length: proxy.size.height)
                } action: { extent in
                    offset = extent.offset
                    contentHeight = extent.length
                }
        }
        .coordinateSpace(name: verticalFadingScrollSpace)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            viewportHeight = height
        }
        // Progressive blur at an edge with more behind it, like Craft's
        // toolbar; under Reduce Motion only the fade below. Built only while
        // the edge fades, so an idle list blurs nothing.
        .overlay(alignment: .top) {
            if !reduceMotion, style.blurEnabled, style.blurHeight > 0, fadesTop {
                VariableBlur(edge: .top, maxRadius: style.blurRadius)
                    .frame(height: style.blurHeight + style.overscan)
                    .padding(.horizontal, -style.overscan)
                    .padding(.top, -style.overscan)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if !reduceMotion, style.blurEnabled, style.blurHeight > 0, fadesBottom {
                VariableBlur(edge: .bottom, maxRadius: style.blurRadius)
                    .frame(height: style.blurHeight + style.overscan)
                    .padding(.horizontal, -style.overscan)
                    .padding(.bottom, -style.overscan)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .mask(
            VStack(spacing: 0) {
                LinearGradient(stops: EasedFade.stops(towardOpaque: true), startPoint: .top, endPoint: .bottom)
                    .frame(height: fadesTop ? style.fadeHeight : 0)
                Rectangle()
                LinearGradient(stops: EasedFade.stops(towardOpaque: false), startPoint: .top, endPoint: .bottom)
                    .frame(height: fadesBottom ? style.fadeHeight : 0)
            }
        )
        .animation(DroppyAnimation.state, value: fadesTop)
        .animation(DroppyAnimation.state, value: fadesBottom)
    }
}

private let verticalFadingScrollSpace = "killteeVerticalFadingScroll"

/// A fade that eases in and out instead of running straight: a straight
/// ramp shows its two ends as lines.
enum EasedFade {
    static func stops(towardOpaque: Bool) -> [Gradient.Stop] {
        (0...8).map { index in
            let t = Double(index) / 8
            // Smootherstep: flat at both ends.
            let eased = t * t * t * (t * (t * 6 - 15) + 10)
            return Gradient.Stop(color: .black.opacity(towardOpaque ? eased : 1 - eased), location: t)
        }
    }
}

