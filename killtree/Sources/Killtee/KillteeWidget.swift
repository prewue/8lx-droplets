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
                case .confirm(let target):
                    ConfirmScreen(droplet: droplet, target: target)
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
            refresh: droplet.refresh
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
    }
}

private struct RowView: View {
    @ObservedObject var droplet: KillteeDroplet
    let row: ListRow

    var body: some View {
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
        TreeBranchShape(isFirst: isFirst, isLast: isLast, trunkX: Self.trunkX, twigEnd: Self.twigEnd, reach: Self.reach)
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
        path.addLine(to: CGPoint(x: x, y: isLast ? mid - r : rect.maxY))
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

/// Droppy's glass disc, tinted red, with a red cross.
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

/// The group's close disc, or what it is doing while it closes.
private struct CloseOrStatus: View {
    let status: String?
    let help: String
    let action: () -> Void

    var body: some View {
        ZStack {
            if let status {
                HStack(spacing: DroppySpacing.xs) {
                    ProgressView().controlSize(.mini)
                    Text(verbatim: status)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                }
                .transition(DroppyTransition.element)
            } else {
                CloseDisc(size: 24, help: help, action: action)
                    .transition(DroppyTransition.element)
            }
        }
        .animation(DroppyAnimation.state, value: status)
    }
}

/// An app or a vendor's services, and its processes under it while open.
/// With its app closed it sits back at half opacity, until it is pointed at
/// or opened.
private struct GroupBlock: View {
    @ObservedObject var droplet: KillteeDroplet
    let group: AppGroup
    let children: [ProcessCluster]?

    @State private var isHovering = false

    private var subtitle: String {
        if group.isHost { return "Runs KillTee" }
        let background = group.backgroundProcesses.count
        if background > 0 { return "\(background) in the background" }
        let count = group.processes.count
        return "\(count) process\(count == 1 ? "" : "es")"
    }

    var body: some View {
        let isOpen = children != nil
        VStack(spacing: 0) {
            HStack(spacing: DroppySpacing.sm) {
                Button {
                    droplet.toggleExpanded(group.id)
                } label: {
                    HStack(spacing: 0) {
                        DisclosureChevron(isOpen: isOpen, isRevealed: group.isExpandable && (isOpen || isHovering))
                        AppIcon(path: group.iconPath, size: 26)
                            .padding(.trailing, DroppySpacing.sm)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: group.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                                .lineLimit(1)
                            Text(verbatim: subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: DroppySpacing.sm)
                        Text(verbatim: Bytes.text(group.memory))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                            .contentTransition(.numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.name), \(subtitle)")
                .accessibilityHint(isOpen ? "Hides its processes" : "Shows its processes")

                if group.isHost {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .frame(width: 24, height: 24)
                } else {
                    CloseOrStatus(status: droplet.working[group.id], help: "Close \(group.name) completely") {
                        droplet.requestClose(group.id)
                    }
                }
            }
            .frame(height: KillteeDroplet.groupRowHeight)

            if let children {
                VStack(spacing: 0) {
                    ForEach(Array(children.enumerated()), id: \.element.id) { index, cluster in
                        ClusterRow(
                            cluster: cluster,
                            isFirst: index == 0,
                            isLast: index == children.count - 1,
                            isBusy: droplet.working["\(group.id)#\(cluster.id)"] != nil,
                            onClose: group.isHost || cluster.first.kind == .system || cluster.first.isPrivileged
                                ? nil
                                : { droplet.requestClose(.cluster(group: group.id, cluster: cluster.id)) }
                        )
                    }
                }
                .padding(.top, KillteeDroplet.blockChildrenGap)
                .padding(.bottom, KillteeDroplet.blockBottomInset)
                .transition(DroppyTransition.element)
            }
        }
        .padding(.horizontal, DroppySpacing.sm)
        .background { BlockSurface(isOpen: isOpen, isHovering: isHovering) }
        .opacity(isOpen || group.isAppRunning || isHovering ? 1 : KillteeDroplet.closedAppOpacity)
        .onHover { isHovering = $0 }
        .animation(DroppyAnimation.hoverQuick, value: isHovering)
    }
}

/// One process of an app group, or the same one several times.
private struct ClusterRow: View {
    let cluster: ProcessCluster
    var isFirst = false
    var isLast = false
    var isBusy = false
    var onClose: (() -> Void)?

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

    var body: some View {
        let process = cluster.first
        HStack(spacing: DroppySpacing.sm) {
            TreeBranch(isFirst: isFirst, isLast: isLast)
                .padding(.trailing, -DroppySpacing.sm)
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(process.keepAlive ? KillteeDroplet.closeTint : AdaptiveColors.notchSurfaceTertiaryText)
                .frame(width: childSymbolWidth, alignment: .leading)
            Text(verbatim: process.name)
                .font(.system(size: 12))
                .foregroundStyle(process.kind.isBackground ? AdaptiveColors.notchSurfacePrimaryText : AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            if cluster.count > 1 {
                Text(verbatim: "×\(cluster.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
            }
            ForEach(tags, id: \.self) { Tag(text: $0) }
            Spacer(minLength: DroppySpacing.sm)
            Text(verbatim: Bytes.text(cluster.memory))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            RowCloseSlot(isVisible: isHovering, isBusy: isBusy, help: "End \(process.name)", action: onClose)
        }
        .frame(height: KillteeDroplet.processRowHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}

/// The small close disc a child row shows under the pointer, in the same
/// column as the group's own.
private struct RowCloseSlot: View {
    let isVisible: Bool
    let isBusy: Bool
    let help: String
    let action: (() -> Void)?

    var body: some View {
        ZStack {
            if isBusy {
                ProgressView().controlSize(.mini)
            } else if isVisible, let action {
                CloseDisc(size: 20, help: help, action: action)
                    .transition(DroppyTransition.element)
            }
        }
        .frame(width: 24, height: 20)
        .animation(DroppyAnimation.hoverQuick, value: isVisible)
    }
}

/// A terminal tool and its sessions, or a server and its processes.
private struct TaskBlock: View {
    @ObservedObject var droplet: KillteeDroplet
    let task: TaskGroup
    let isOpen: Bool

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DroppySpacing.sm) {
                Button {
                    droplet.toggleExpanded(task.id)
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
                            .padding(.trailing, DroppySpacing.sm)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.xs) {
                                Text(verbatim: task.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if let age = task.age {
                                    Text(verbatim: age)
                                        .font(.system(size: 11))
                                        .monospacedDigit()
                                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                                }
                            }
                            HStack(spacing: DroppySpacing.xsm) {
                                Text(verbatim: task.subtitle)
                                    .font(.system(size: 11))
                                    .monospacedDigit()
                                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                                    .lineLimit(1)
                                ForEach(task.badges, id: \.self) { Tag(text: $0) }
                            }
                        }
                        Spacer(minLength: DroppySpacing.sm)
                        Text(verbatim: Bytes.text(task.memory))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                            .contentTransition(.numericText())
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(task.name), \(task.subtitle)")

                CloseOrStatus(
                    status: droplet.working[task.id],
                    help: task.category == .terminal ? "End every \(task.name) session" : "Stop \(task.name)"
                ) {
                    droplet.requestClose(.task(task.id))
                }
            }
            .frame(height: KillteeDroplet.groupRowHeight)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(Array(task.items.enumerated()), id: \.element.id) { index, item in
                        TaskItemRow(
                            item: item,
                            isFirst: index == 0,
                            isLast: index == task.items.count - 1,
                            isBusy: droplet.working[item.id] != nil,
                            onClose: { droplet.requestClose(.item(task: task.id, item: item.id)) }
                        )
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
    var isFirst = false
    var isLast = false
    let isBusy: Bool
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            TreeBranch(isFirst: isFirst, isLast: isLast)
                .padding(.trailing, -DroppySpacing.sm)
            Image(systemName: item.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                .frame(width: childSymbolWidth, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.xsm) {
                Text(verbatim: item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
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
            Text(verbatim: Bytes.text(item.memory))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            RowCloseSlot(isVisible: isHovering, isBusy: isBusy, help: "End \(item.title)", action: onClose)
        }
        .frame(height: KillteeDroplet.processRowHeight)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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

/// A vendor or a service KillTee keeps closed, with the way back.
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
                HStack(spacing: DroppySpacing.xsm) {
                    Text(verbatim: "Closed \(ago)")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .lineLimit(1)
                    if closed.reclosed > 0 {
                        Tag(text: "Held off \(closed.reclosed)")
                    }
                }
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

// MARK: - Confirm

private struct ConfirmScreen: View {
    @ObservedObject var droplet: KillteeDroplet
    let target: ConfirmTarget

    private struct Copy {
        var icon: String?
        var symbol = "xmark.circle"
        var title: String
        var note: String
        var action = "Close all"
    }

    private var copy: Copy {
        switch target {
        case .group(let id):
            guard let group = droplet.group(id) else { return Copy(title: "Close it completely?", note: "") }
            let quitsOnly = !group.hasBackground && group.jobs.isEmpty
        return Copy(
            icon: group.iconPath,
            title: quitsOnly ? "Quit \(group.name)?" : title(of: group),
            note: note(of: group),
            action: quitsOnly ? "Quit" : (group.closableProcesses.isEmpty ? "Turn off" : "Close all")
        )
        case .task(let id):
            guard let task = droplet.task(id) else { return Copy(title: "Close it?", note: "") }
            if task.category == .terminal {
                let sessions = task.items.count
                return Copy(
                    symbol: "terminal",
                    title: "End every \(task.name) session?",
                    note: "\(sessions) session\(sessions == 1 ? "" : "s") in the terminal end now; what they had not saved is lost. If KillTee's own conversation runs in one of them, it ends too.",
                    action: "End all"
                )
            }
            return Copy(
                symbol: task.symbol,
                title: "Stop \(task.name)?",
                note: task.job != nil
                    ? "Its launchd job is taken out so it stays stopped. Restore starts it again."
                    : "\(task.processes.count) process\(task.processes.count == 1 ? "" : "es") end. Nothing starts \(task.processes.count == 1 ? "it" : "them") again.",
                action: "Stop"
            )
        case let .item(taskID, itemID):
            guard let task = droplet.task(taskID), let item = task.items.first(where: { $0.id == itemID }) else {
                return Copy(title: "End it?", note: "")
            }
            let isSession = task.category == .terminal
            return Copy(
                symbol: item.symbol,
                title: isSession ? "End \(task.name) in \(item.title)?" : "End \(item.title)?",
                note: isSession
                    ? "This session ends now; what it had not saved is lost."
                    : (task.job?.keepAlive == true
                        ? "launchd may start it again; stop the whole service to keep it stopped."
                        : "\(item.count) process\(item.count == 1 ? "" : "es") and their children end."),
                action: "End"
            )
        case let .cluster(groupID, clusterID):
            guard let group = droplet.group(groupID),
                  let cluster = ProcessCluster.clusters(of: group.processes).first(where: { $0.id == clusterID }) else {
                return Copy(title: "End it?", note: "")
            }
            return Copy(
                icon: group.iconPath,
                title: "End \(cluster.first.name)\(cluster.count > 1 ? " ×\(cluster.count)" : "")?",
                note: cluster.first.keepAlive
                    ? "It restarts itself: launchd starts it again at once. Close \(group.name) as a whole to keep it closed."
                    : "Only this; the rest of \(group.name) keeps running.",
                action: "End"
            )
        }
    }

    private func title(of group: AppGroup) -> String {
        group.closableProcesses.isEmpty ? "Turn off \(group.name) at login?" : "Close \(group.name) completely?"
    }

    private func note(of group: AppGroup) -> String {
        if !group.hasBackground, group.jobs.isEmpty {
            return "\(group.name) quits the normal way; if it has unsaved work, it asks first."
        }
        if group.closableProcesses.isEmpty {
            let jobs = group.startupJobs.count
            return "\(jobs) launchd job\(jobs == 1 ? "" : "s") stop starting at login" + reopenLine(group)
        }
        let background = group.backgroundProcesses.count
        var subject: [String] = []
        if group.isAppRunning { subject.append(group.runningApps.joined(separator: ", ")) }
        if background > 0 { subject.append("\(background) background process\(background == 1 ? "" : "es")") }
        var line = subject.isEmpty ? "" : subject.joined(separator: " and ") + ". "
        line += "Nothing of it starts again" + reopenLine(group)
        if group.isShared {
            line += " Every \(group.organization ?? "vendor") app uses these."
        }
        if group.privilegedCount > 0 {
            let count = group.privilegedCount
            line += droplet.includesSystem
                ? " \(count) system service\(count == 1 ? "" : "s") will ask for your password."
                : " \(count) system service\(count == 1 ? "" : "s") stay\(count == 1 ? "s" : "") on."
        }
        return line
    }

    private func reopenLine(_ group: AppGroup) -> String {
        guard droplet.autoRestore else { return " until you restore it." }
        return group.isShared
            ? " until you open one of \(group.organization ?? "its") apps."
            : " until you open \(group.name)."
    }

    var body: some View {
        let copy = copy
        VStack(spacing: DroppySpacing.md) {
            Spacer(minLength: 0)
            if let icon = copy.icon {
                AppIcon(path: icon, size: 34)
            } else {
                Image(systemName: copy.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KillteeDroplet.closeTint)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 34 * DroppyRadius.appIconCornerRatio, style: .continuous)
                            .fill(AdaptiveColors.notchSurfaceCardFill)
                    )
            }
            VStack(spacing: DroppySpacing.xs) {
                Text(verbatim: copy.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: copy.note)
                    .font(.system(size: 11))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .lineLimit(3)
                    .frame(maxWidth: 360)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: DroppySpacing.sm) {
                Button { droplet.cancelConfirmation() } label: {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.lg)
                        .frame(height: KillteeDroplet.navHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle())
                .keyboardShortcut(.cancelAction)
                Button { droplet.confirmClose() } label: {
                    Text(verbatim: copy.action)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, DroppySpacing.lg)
                        .frame(height: KillteeDroplet.navHeight)
                }
                .buttonStyle(DroppyGlassButtonStyle(fill: .tinted(KillteeDroplet.closeTint)))
                .keyboardShortcut(.defaultAction)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Paired

/// Paired: the memory held in the background, and the heaviest vendor with
/// its close disc.
private struct PairedView: View {
    @ObservedObject var droplet: KillteeDroplet

    var body: some View {
        let top = droplet.visibleGroups.first
        VStack(alignment: .leading, spacing: DroppySpacing.xs) {
            HStack(spacing: DroppySpacing.xsm) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KillteeDroplet.closeTint)
                Text("KillTee")
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
