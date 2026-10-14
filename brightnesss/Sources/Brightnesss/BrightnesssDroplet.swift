import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. It only creates the droplet: it runs before the host is ready.
@objc(BrightnesssPrincipal)
public final class BrightnesssPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { BrightnesssDroplet() }
}

public enum BrightnesssScreen: Equatable {
    case welcome
    case control
}

/// Why XDR is held at 100 right now.
public enum XDRBlock: Equatable {
    case battery
    case heat

    var title: String {
        switch self {
        case .battery: return "XDR off on battery"
        case .heat: return "XDR off, the Mac is hot"
        }
    }
}

/// Brightnesss: the built-in display past 100 and below 0, from the shelf.
@MainActor
public final class BrightnesssDroplet: NSObject, ObservableObject, Droplet {
    public nonisolated static let id: DropletID = "brightnesss"

    static let widgetID: ShelfWidgetID = "brightnesss"

    private var host: DropletHost?

    let engine = BrightnessEngine()
    let toggles = SystemToggles()
    let power = PowerGuard()
    let keys = BrightnessKeys()
    /// What the notch strip shows; it observes this so its digits roll.
    let hudModel = LevelHUDModel()

    @Published public private(set) var screen: BrightnesssScreen = .control
    /// The engine's level, mirrored so the views redraw.
    @Published public private(set) var level: Double = 100
    @Published public private(set) var maximum: Double = 100
    @Published public private(set) var xdrBlock: XDRBlock?

    private let layoutSubject = PassthroughSubject<ShelfWidgetID, Never>()

    private enum Keys {
        static let hasSeenWelcome = "hasSeenWelcome"
        static let xdrOffOnBattery = "xdrOffOnBattery"
        static let xdrOffWhenHot = "xdrOffWhenHot"
        static let extendsKeys = "extendsKeys"
        static let showsHUD = "showsHUD"
    }

    // MARK: Lifecycle

    public func activate(host: DropletHost) throws {
        self.host = host
        let dryRun = host.environment.isHarness
        engine.log = { [weak self] message in self?.host?.log.info(message) }
        engine.onExternalChange = { [weak self] in self?.engineDidChange() }
        power.onChange = { [weak self] in self?.enforceGuards(announce: true) }
        keys.handler = { [weak self] up, fine in self?.handleBrightnessKey(up: up, fine: fine) ?? false }
        engine.start(dryRun: dryRun)
        toggles.start(dryRun: dryRun)
        power.start(dryRun: dryRun)
        if !dryRun, extendsKeys {
            keys.start()
            if keys.isArmed {
                host.log.info("brightness keys tap armed")
            } else {
                host.log.notice("brightness keys: Accessibility not granted to Droppy, the keys stop at the panel's ends")
            }
        }
        level = engine.level
        maximum = engine.maximum
        screen = hasSeenWelcome ? .control : .welcome
        enforceGuards(announce: false)
        host.log.info("Brightnesss activated at \(Int(level)), ceiling \(Int(maximum))")
    }

    public func deactivate() {
        keys.stop()
        engine.stop()
        toggles.stop()
        power.stop()
        engine.onExternalChange = nil
        engine.log = nil
        power.onChange = nil
        keys.handler = nil
        host = nil
    }

    // MARK: Level

    /// The ceiling the slider may reach now: 100 while a guard holds XDR off.
    public var effectiveMaximum: Double {
        xdrBlock == nil ? maximum : min(maximum, 100)
    }

    var zone: BrightnessZone { engine.zone }

    public var supportsXDR: Bool { maximum > 100 }

    public func setLevel(_ requested: Double) {
        engine.set(min(requested, effectiveMaximum))
        level = engine.level
        maximum = engine.maximum
    }

    /// The sun: full XDR from anywhere at or under 100, back to 100 from XDR.
    public func toggleXDR() {
        setLevel(zone == .xdr ? 100 : effectiveMaximum)
    }

    /// The dial came to rest: the level is whole now.
    public func noteDialSettled() {
        setLevel(level.rounded())
    }

    // MARK: Keys

    /// A brightness key. Ours when it goes into or moves inside the dim and
    /// XDR zones; the system's anywhere in the panel's own range, where macOS
    /// moves the panel, Droppy shows its HUD and the engine follows.
    private func handleBrightnessKey(up: Bool, fine: Bool) -> Bool {
        let step = fine ? Self.keyStep / 4 : Self.keyStep
        let crossesFloor = !up && level <= 0
        let crossesCeiling = up && level >= 100 && effectiveMaximum > 100
        guard zone != .normal || crossesFloor || crossesCeiling else {
            // Droppy draws its own HUD for this press and waits for ours to go
            // first, so ours goes now.
            host?.hud.dismiss(id: Self.levelHUDID)
            return false
        }
        setLevel(level + (up ? step : -step))
        presentLevelHUD()
        return true
    }

    static let levelHUDID = "brightnesss.level"

    /// The level on the notch after an owned key press, instead of the
    /// system's brightness HUD, which the swallowed press never shows.
    private func presentLevelHUD() {
        guard let host, showsHUD else { return }
        withAnimation(DroppyAnimation.state) {
            hudModel.level = level
            hudModel.zone = zone
        }
        let model = hudModel
        let request = DropletHUDRequest(
            id: Self.levelHUDID,
            duration: 0.9,
            // High so it takes the notch from Droppy's own brightness HUD at
            // once when a press crosses out of the panel's range.
            priority: .high,
            accessibilityLabel: "\(zoneTitle), \(levelText)"
        ) {
            LevelHUDStrip(model: model)
        }
        _ = host.hud.present(request)
    }

    /// The shelf opened: the keys may have moved the panel while nobody watched.
    public func refreshFromHardware() {
        engine.refresh()
        engineDidChange()
    }

    private func engineDidChange() {
        level = engine.level
        maximum = engine.maximum
        enforceGuards(announce: false)
        // The keys' last step switched the backlight off before our tap could
        // take the press: with the keys extended, that press meant "dimmer",
        // so the panel comes back at its floor with the first step of dimming.
        if engine.panelIsOff, extendsKeys {
            setLevel(-Self.keyStep)
            presentLevelHUD()
        }
    }

    /// One press past the ends: half a panel step, 32 to a zone.
    static let keyStep = 100.0 / 32

    // MARK: Guards

    private func enforceGuards(announce: Bool) {
        let block: XDRBlock?
        if power.isOnBattery, xdrOffOnBattery {
            block = .battery
        } else if power.isHot, xdrOffWhenHot {
            block = .heat
        } else {
            block = nil
        }
        if block != xdrBlock {
            xdrBlock = block
        }
        guard let block, level > 100 else { return }
        setLevel(100)
        if announce, showsHUD { presentGuardHUD(block) }
    }

    private func presentGuardHUD(_ block: XDRBlock) {
        guard let host else { return }
        let text = block.title
        let request = DropletHUDRequest(
            id: "brightnesss.guard",
            duration: 2.5,
            priority: .normal,
            accessibilityLabel: text
        ) {
            // The strip spans the camera housing: content at the two outer
            // edges and nothing in the middle.
            HStack(spacing: 0) {
                Image(systemName: "sun.max.trianglebadge.exclamationmark")
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                Spacer(minLength: 0)
                Text(verbatim: text)
                    .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        }
        _ = host.hud.present(request)
    }

    // MARK: Screens

    public func finishWelcome() {
        host?.preferences.setValue(true, forKey: Keys.hasSeenWelcome)
        show(.control)
    }

    func show(_ target: BrightnesssScreen) {
        guard screen != target else { return }
        screen = target
        publishLayoutChange()
    }

    public func openSettings() {
        _ = host?.workspace.openSettings()
    }

    private func publishLayoutChange() {
        layoutSubject.send(Self.widgetID)
        host?.shelf.invalidateLayout(for: Self.widgetID)
    }

    // MARK: Preferences

    private func preference(_ key: String, default value: Bool) -> Bool {
        host?.preferences.value(forKey: key, default: value) ?? value
    }

    var hasSeenWelcome: Bool { preference(Keys.hasSeenWelcome, default: false) }

    public var xdrOffOnBattery: Bool { preference(Keys.xdrOffOnBattery, default: true) }
    public var xdrOffWhenHot: Bool { preference(Keys.xdrOffWhenHot, default: true) }
    public var extendsKeys: Bool { preference(Keys.extendsKeys, default: true) }
    public var showsHUD: Bool { preference(Keys.showsHUD, default: true) }

    /// Whether the keys tap is up: Accessibility granted and the switch on.
    public var keysAreExtended: Bool { keys.isArmed }
    public var accessibilityGranted: Bool { BrightnessKeys.isTrusted }

    public var xdrOffOnBatteryBinding: Binding<Bool> {
        Binding(
            get: { self.xdrOffOnBattery },
            set: { self.host?.preferences.setValue($0, forKey: Keys.xdrOffOnBattery); self.enforceGuards(announce: true) }
        )
    }

    public var xdrOffWhenHotBinding: Binding<Bool> {
        Binding(
            get: { self.xdrOffWhenHot },
            set: { self.host?.preferences.setValue($0, forKey: Keys.xdrOffWhenHot); self.enforceGuards(announce: true) }
        )
    }

    public var extendsKeysBinding: Binding<Bool> {
        Binding(
            get: { self.extendsKeys },
            set: { on in
                self.host?.preferences.setValue(on, forKey: Keys.extendsKeys)
                if on { self.keys.start() } else { self.keys.stop() }
                self.objectWillChange.send()
            }
        )
    }

    /// Asks Droppy for Accessibility, then installs the keys tap.
    public func requestAccessibility() {
        guard let host else { return }
        Task { @MainActor [weak self] in
            let status = await host.permissions.request(.accessibility)
            guard let self else { return }
            if status == .denied { host.permissions.openSystemSettings(for: .accessibility) }
            if self.extendsKeys { self.keys.start() }
            self.objectWillChange.send()
        }
    }

    public var showsHUDBinding: Binding<Bool> {
        Binding(
            get: { self.showsHUD },
            set: { self.host?.preferences.setValue($0, forKey: Keys.showsHUD) }
        )
    }

    // MARK: Formatting

    /// "128%", "72%", "-20%".
    public var levelText: String {
        "\(Int(level.rounded()))%"
    }

    static let xdrColor = Color(red: 1, green: 0.6, blue: 0.2)
    static let dimColor = Color(red: 1, green: 0.33, blue: 0.3)

    public var zoneTitle: String {
        if let xdrBlock { return xdrBlock.title }
        switch zone {
        case .dim: return "Dimmed"
        case .normal: return "Brightness"
        case .xdr: return "XDR"
        }
    }

    /// The word beside the sun outside the panel's range, or nothing.
    public var zoneBadge: String? {
        switch zone {
        case .dim: return "Dimmed"
        case .normal: return nil
        case .xdr: return "XDR"
        }
    }

    public var zoneSymbol: String { Self.symbol(for: zone) }

    /// The level's own colour: orange past 100, red below 0.
    public var zoneColor: Color {
        Self.color(for: zone)
    }

    static func color(for zone: BrightnessZone) -> Color {
        switch zone {
        case .dim: return dimColor
        case .normal: return AdaptiveColors.notchSurfaceSecondaryText
        case .xdr: return xdrColor
        }
    }

    static func symbol(for zone: BrightnessZone) -> String {
        switch zone {
        case .dim: return "sun.min.fill"
        case .normal: return "sun.max"
        case .xdr: return "sun.max.fill"
        }
    }
}

// MARK: - Shelf widget

extension BrightnesssDroplet: ShelfWidgetProviding {
    /// Space the host's corner clearance takes, top and bottom.
    static let hostInsets: CGFloat = DroppySpacing.sm * 2
    static let navHeight: CGFloat = 28
    static let welcomeHeight: CGFloat = 195
    /// Nav row, the dial and the gap between.
    static let controlHeight: CGFloat = navHeight + DroppySpacing.md + LevelDial.soloHeight

    var widgetHeight: CGFloat {
        switch screen {
        case .welcome: return Self.hostInsets + Self.welcomeHeight
        case .control: return Self.hostInsets + Self.controlHeight
        }
    }

    var layoutTraits: ShelfWidgetLayoutTraits {
        ShelfWidgetLayoutTraits(
            preferredSoloWidth: 420,
            preferredPairedWidth: 210,
            contentHeight: .fixed(widgetHeight)
        )
    }

    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Brightnesss",
                systemImage: "sun.max.fill",
                layoutTraits: layoutTraits,
                searchKeywords: ["brightness", "xdr", "dim", "display", "screen", "night shift", "true tone"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        if !context.isPreview, host?.environment.isHarness == false {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshFromHardware()
                // Droppy re-creates its own media key tap now and then, which
                // puts it ahead of ours; ours has to see the press first to
                // catch it at the ends. Re-arming puts it back in front.
                if self.extendsKeys { self.keys.rearm() }
            }
        }
        return AnyView(BrightnesssWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

extension BrightnesssDroplet: ShelfWidgetDynamicLayoutProviding {
    public func currentLayoutTraits(for id: ShelfWidgetID) -> ShelfWidgetLayoutTraits? {
        id == Self.widgetID ? layoutTraits : nil
    }

    public var shelfWidgetLayoutInvalidationPublisher: AnyPublisher<ShelfWidgetID, Never> {
        layoutSubject.eraseToAnyPublisher()
    }
}

// MARK: - HUD

extension BrightnesssDroplet: HUDPresenting {}

/// The strip's state, kept outside the request so the strip that is already
/// up sees the next press and rolls its digits instead of being rebuilt.
@MainActor
final class LevelHUDModel: ObservableObject {
    @Published var level: Double = 100
    @Published var zone: BrightnessZone = .normal
}

/// The sun and its word at the far left, the level at the far right, nothing
/// under the camera housing in between. Digits roll like Droppy's own HUD.
private struct LevelHUDStrip: View {
    @ObservedObject var model: LevelHUDModel

    var body: some View {
        let color = BrightnesssDroplet.color(for: model.zone)
        HStack(spacing: 0) {
            HStack(spacing: DroppySpacing.xs) {
                Image(systemName: BrightnesssDroplet.symbol(for: model.zone))
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                if model.zone != .normal {
                    Text(verbatim: model.zone == .xdr ? "XDR" : "DIM")
                        .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .bold, design: .rounded))
                        .transition(DroppyTransition.compactContent)
                }
            }
            .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(verbatim: "\(Int(model.level.rounded()))%")
                .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: model.level))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        }
        .frame(maxWidth: .infinity)
        .animation(DroppyAnimation.state, value: model.level)
        .animation(DroppyAnimation.state, value: model.zone)
    }
}

// MARK: - Settings pane

extension BrightnesssDroplet: SettingsPaneProviding {
    public func makeSettingsPane(context: SettingsPaneContext) -> AnyView {
        AnyView(BrightnesssSettings(droplet: self))
    }

    public var settingsSearchEntries: [SettingsSearchEntry] {
        [
            SettingsSearchEntry(title: "Turn off XDR on battery", keywords: ["battery", "xdr", "power"]),
            SettingsSearchEntry(title: "Turn off XDR when the Mac runs hot", keywords: ["thermal", "heat", "xdr"]),
            SettingsSearchEntry(title: "Brightness keys go past the ends", keywords: ["keys", "keyboard", "accessibility"])
        ]
    }
}
