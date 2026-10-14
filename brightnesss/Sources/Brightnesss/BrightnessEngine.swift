import AppKit
import Metal
import QuartzCore

/// Where a level sits: below the panel's minimum, inside its range, or above it.
enum BrightnessZone: Equatable {
    case dim
    case normal
    case xdr
}

/// The pure mapping behind the level, kept free of AppKit.
enum BoostMath {
    /// Headroom at or below this is noise, not a panel that can boost.
    static let readyThreshold = 1.05
    /// Shown instead of the target while the panel has not ramped EDR yet;
    /// a little above 1.0 is itself what asks macOS to ramp.
    static let pendingFactor = 1.12
    /// What is left of the picture at -100: the dim overlay never goes fully black.
    static let dimFloor = 0.05
    /// The panel's lowest lit step. One below it, 0.0, is the backlight off:
    /// what the brightness keys do on their last press. The level's 0 is this
    /// step, so the dim zone starts from a picture, not from a black screen.
    static let panelFloor: Float = 1.0 / 16

    /// The panel value for a level inside its own range.
    static func panel(for level: Double) -> Float {
        let t = Float(min(max(level, 0), 100) / 100)
        return panelFloor + (1 - panelFloor) * t
    }

    /// The level a panel value means; 0 at the floor and below it.
    static func level(forPanel value: Float) -> Double {
        guard value > panelFloor else { return 0 }
        return (Double((value - panelFloor) / (1 - panelFloor)) * 100).rounded()
    }

    /// The level's ceiling: 100 without usable headroom, otherwise up to 200.
    static func maximum(potentialHeadroom: Double) -> Double {
        guard potentialHeadroom > readyThreshold else { return 100 }
        return (100 * min(potentialHeadroom, 2)).rounded()
    }

    /// The EDR multiplier for a level above 100, exponential across the boost
    /// region because perceived brightness is roughly logarithmic.
    static func overlayFactor(level: Double, maximum: Double, currentHeadroom: Double, potentialHeadroom: Double) -> Double {
        guard level > 100, maximum > 100, potentialHeadroom > readyThreshold else { return 1 }
        guard currentHeadroom > readyThreshold else { return pendingFactor }
        let t = min(1, (level - 100) / (maximum - 100))
        return pow(currentHeadroom, t)
    }

    /// How much of the picture a level below 0 keeps: 1 at 0, the floor at -100.
    static func dimFactor(level: Double) -> Double {
        guard level < 0 else { return 1 }
        return 1 + (max(level, -100) / 100) * (1 - dimFloor)
    }
}

// MARK: - DisplayServices

/// The private DisplayServices entry points, the only way to the built-in
/// panel's own brightness on Apple Silicon. Resolved once; every one is nil
/// on a Mac without them, and the engine then leaves the panel's range alone.
private enum DisplayServices {
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool

    nonisolated(unsafe) private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
    )

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: type)
    }

    static let set = symbol("DisplayServicesSetBrightness", as: SetBrightness.self)
    static let get = symbol("DisplayServicesGetBrightness", as: GetBrightness.self)
    static let canChange = symbol("DisplayServicesCanChangeBrightness", as: CanChange.self)
}

// MARK: - Engine

/// One level for the built-in display, from -100 to the panel's XDR ceiling.
///
/// 0 to 100 is the panel's own brightness (DisplayServices). Below 0 a black
/// overlay under Droppy's own windows takes the picture down past the
/// backlight's minimum, so the shelf stays bright over a dimmed desktop. Above
/// 100 an invisible EDR overlay multiplies the whole desktop into the panel's
/// HDR headroom, the way BrightIntosh and Crisp do.
@MainActor
final class BrightnessEngine {
    static let minimum: Double = -100

    private(set) var level: Double = 100
    private(set) var isDryRun = false
    private(set) var hardwareAvailable = false
    private(set) var displayID: CGDirectDisplayID = CGMainDisplayID()
    private(set) var potentialHeadroom: Double = 1

    /// Fired when the level or the ceiling changed without a `set`: the
    /// brightness keys, Control Center, a display change, headroom going away.
    var onExternalChange: (@MainActor () -> Void)?
    var log: (@MainActor (String) -> Void)?

    private let overlay = EDROverlay()
    private let dim = DimOverlay()
    private var expectedHardware: Float?
    /// Our last panel write: DisplayServices glides towards it, and a reading
    /// between where the panel was and where we sent it is that glide, never
    /// the user at the keys. Cleared once the panel arrives.
    private var writeWindow: (from: Float, to: Float)?
    /// The panel is read every 300 ms rather than through
    /// DisplayServices' change notification: that registration is one per
    /// process, and Droppy holds it for its own brightness HUD.
    private var hardwarePoll: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var headroomPoll: Task<Void, Never>?
    private var fastPollUntil: Date?
    private var overlayRetire: Task<Void, Never>?
    private var reconfigure: Task<Void, Never>?
    private let hardwareQueue = DispatchQueue(label: "brightnesss.hardware", qos: .userInteractive)

    var maximum: Double { BoostMath.maximum(potentialHeadroom: potentialHeadroom) }

    /// The backlight is off: the keys' last step took it there, not us.
    var panelIsOff: Bool { expectedHardware.map { $0 < 0.001 } ?? false }

    var zone: BrightnessZone {
        if level < 0 { return .dim }
        if level > 100 { return .xdr }
        return .normal
    }

    /// Whether this Mac can push past 100 at all.
    var supportsXDR: Bool { maximum > 100 }

    // MARK: Lifecycle

    func start(dryRun: Bool) {
        isDryRun = dryRun
        if dryRun {
            hardwareAvailable = true
            potentialHeadroom = 2
            level = 100
            return
        }
        resolveDisplay()
        readHardware()
        startHardwarePoll()
        observe()
        log?("engine started on display \(displayID), hardware \(hardwareAvailable ? "available" : "unavailable"), headroom \(potentialHeadroom)")
    }

    func stop() {
        headroomPoll?.cancel()
        headroomPoll = nil
        hardwarePoll?.cancel()
        hardwarePoll = nil
        overlayRetire?.cancel()
        overlayRetire = nil
        reconfigure?.cancel()
        reconfigure = nil
        guard !isDryRun else { return }
        overlay.remove()
        dim.remove()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
    }

    // MARK: Setting

    func set(_ requested: Double) {
        level = min(max(requested, Self.minimum), maximum)
        apply()
    }

    /// Re-reads the panel after a stretch nobody watched it, when the shelf opens.
    func refresh() {
        guard !isDryRun else { return }
        refreshHeadroom()
        hardwareDidChange()
    }

    private func apply() {
        guard !isDryRun else { return }
        applyHardware()
        applyDim()
        syncOverlay()
    }

    // MARK: Hardware

    private func resolveDisplay() {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        displayID = ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        refreshHeadroom()
    }

    private func readHardware() {
        guard let get = DisplayServices.get else {
            hardwareAvailable = false
            return
        }
        var value: Float = 0
        guard get(displayID, &value) == 0 else {
            hardwareAvailable = false
            return
        }
        hardwareAvailable = DisplayServices.canChange?(displayID) ?? true
        expectedHardware = value
        level = BoostMath.level(forPanel: value)
    }

    private func applyHardware() {
        guard hardwareAvailable, let set = DisplayServices.set else { return }
        let target = BoostMath.panel(for: level)
        if let expectedHardware, abs(expectedHardware - target) < 0.0005 { return }
        writeWindow = (from: expectedHardware ?? target, to: target)
        expectedHardware = target
        let id = displayID
        hardwareQueue.async {
            _ = set(id, target)
        }
    }

    /// The panel changed under us: the brightness keys, Control Center,
    /// auto-brightness. Our own writes echo here too and are told apart by
    /// the value we expect.
    func hardwareDidChange() {
        guard let get = DisplayServices.get else { return }
        var value: Float = 0
        guard get(displayID, &value) == 0 else { return }
        if let expectedHardware, abs(expectedHardware - value) < 0.004 {
            writeWindow = nil
            return
        }
        if let writeWindow,
           value >= min(writeWindow.from, writeWindow.to) - 0.004,
           value <= max(writeWindow.from, writeWindow.to) + 0.004 {
            // A step of the panel's own glide towards what we asked for.
            return
        }
        self.writeWindow = nil
        log?("panel moved to \(value) on its own while the level was \(Int(level)); following it")
        // 0.0 is the backlight off, the keys' last step: the level sits at
        // the floor and the panel is left as the user put it.
        expectedHardware = value
        level = BoostMath.level(forPanel: value)
        // Whatever extra was on is gone: the keys move the panel, not the overlays.
        dim.remove()
        headroomPoll?.cancel()
        headroomPoll = nil
        syncOverlay()
        onExternalChange?()
    }

    private func startHardwarePoll() {
        guard hardwareAvailable, hardwarePoll == nil else { return }
        hardwarePoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled else { return }
                self.hardwareDidChange()
            }
        }
    }

    // MARK: Dim

    private func applyDim() {
        let factor = BoostMath.dimFactor(level: level)
        dim.setOpacity(1 - factor, on: screen)
    }

    // MARK: Overlay

    private var screen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }

    var currentHeadroom: Double {
        Double(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
    }

    /// Re-reads what the panel could do. Returns whether the ceiling moved.
    @discardableResult
    private func refreshHeadroom() -> Bool {
        let before = maximum
        potentialHeadroom = Double(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1)
        return maximum != before
    }

    private func syncOverlay() {
        let factor = BoostMath.overlayFactor(
            level: level, maximum: maximum,
            currentHeadroom: currentHeadroom, potentialHeadroom: potentialHeadroom
        )
        if factor > 1.001 || overlay.isMounted {
            overlay.setFactor(factor, on: screen)
        }
        if level > 100 {
            overlayRetire?.cancel()
            overlayRetire = nil
            startHeadroomPoll()
        } else {
            scheduleOverlayRetire()
        }
    }

    /// Closes the EDR surface once everything is static: closing it exits
    /// EDR mode, and doing that mid-motion flashes the display.
    private func scheduleOverlayRetire() {
        guard overlay.isMounted, overlayRetire == nil else { return }
        overlayRetire = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            self.overlayRetire = nil
            if self.level <= 100 { self.overlay.remove() }
        }
    }

    /// Deliverable headroom drifts with the panel's brightness and thermals
    /// with no notification, so the factor is re-clamped while boosted: every
    /// 500 ms, and every 16 ms for the first 3 s, while macOS ramps EDR in.
    private func startHeadroomPoll() {
        guard headroomPoll == nil else { return }
        fastPollUntil = Date().addingTimeInterval(3)
        headroomPoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let fast = self.flatMap { $0.fastPollUntil.map { Date() < $0 } } ?? false
                try? await Task.sleep(for: .milliseconds(fast ? 16 : 500))
                guard let self, !Task.isCancelled else { return }
                guard self.level > 100 else {
                    self.headroomPoll = nil
                    self.scheduleOverlayRetire()
                    return
                }
                if self.refreshHeadroom(), self.level > self.maximum {
                    self.level = self.maximum
                    self.onExternalChange?()
                }
                self.overlay.setFactor(BoostMath.overlayFactor(
                    level: self.level, maximum: self.maximum,
                    currentHeadroom: self.currentHeadroom, potentialHeadroom: self.potentialHeadroom
                ), on: self.screen)
            }
        }
    }

    // MARK: Observers

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.displaysDidChange() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reapplyAfterWake() }
        })
    }

    /// Reconciles once after a connect or disconnect storm settles: the
    /// geometry and headroom read mid-change are garbage.
    private func displaysDidChange() {
        reconfigure?.cancel()
        reconfigure = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.reconfigure = nil
            self.resolveDisplay()
            if self.level > self.maximum { self.level = self.maximum }
            self.apply()
            self.onExternalChange?()
        }
    }

    private func reapplyAfterWake() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard let self else { return }
            self.applyDim()
            self.overlay.rerender()
            self.hardwareDidChange()
        }
    }
}

// MARK: - Dim overlay

/// A black window over the built-in display, under Droppy's own windows and
/// over everything else, whose opacity is the dimming. It takes no clicks,
/// stays out of screenshots and recordings, and follows the display's frame.
@MainActor
final class DimOverlay {
    private var window: NSWindow?

    var isMounted: Bool { window != nil }

    func setOpacity(_ opacity: Double, on screen: NSScreen?) {
        guard opacity > 0.001 else {
            remove()
            return
        }
        if window == nil {
            guard let screen else { return }
            mount(on: screen)
        }
        guard let window else { return }
        if let screen, window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        window.level = Self.levelUnderHost()
        window.alphaValue = min(opacity, 1 - BoostMath.dimFloor)
    }

    func remove() {
        window?.close()
        window = nil
    }

    private func mount(on screen: NSScreen) {
        let window = NSWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = false
        window.alphaValue = 0
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.sharingType = .none
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
        window.level = Self.levelUnderHost()
        window.orderFrontRegardless()
        self.window = window
    }

    /// One level below Droppy's notch window, so the shelf and the notch are
    /// never dimmed. Found by its class; otherwise the highest ordinary
    /// window the host has up, and failing that one under the pop-up level.
    private static func levelUnderHost() -> NSWindow.Level {
        let shielding = Int(CGShieldingWindowLevel())
        let windows = NSApp.windows.filter { $0.isVisible && $0.level.rawValue < shielding }
        let named = windows.map { (window: $0, name: String(describing: type(of: $0))) }
        if let notch = named.first(where: { $0.name == "NotchWindow" }) ?? named.first(where: { $0.name.contains("Notch") }) {
            return NSWindow.Level(rawValue: notch.window.level.rawValue - 1)
        }
        // The lowest window the host keeps above the menu bar is its panel.
        let elevated = windows.map(\.level.rawValue).filter { $0 > NSWindow.Level.statusBar.rawValue }.min()
        return NSWindow.Level(rawValue: (elevated ?? NSWindow.Level.popUpMenu.rawValue - 1) - 1)
    }
}

// MARK: - EDR overlay

/// A fullscreen, invisible, click-through window showing one EDR colour above
/// 1.0 through a Metal layer with a multiply filter, so everything beneath it
/// is brightened into the panel's HDR headroom. WindowServer honours the filter
/// only while the window keeps presenting, so it re-presents at 5 fps for as
/// long as it exists, at the shielding level where idle promotion never
/// drops the filter. Once mounted it stays alive even at factor 1.0: closing
/// and reopening the EDR surface flashes the display.
@MainActor
final class EDROverlay {
    private var window: NSWindow?
    private var layer: CAMetalLayer?
    private var factor: Double = 1
    private var timer: Timer?
    private var revealed = false
    private var presentsPending = 0
    private var lastPresent = Date()
    private var renderPending = false
    private let device = MTLCreateSystemDefaultDevice()
    private lazy var commandQueue = device?.makeCommandQueue()

    var isMounted: Bool { window != nil }

    @discardableResult
    func setFactor(_ requested: Double, on screen: NSScreen?) -> Bool {
        let clamped = max(1, requested)
        if window == nil {
            guard clamped > 1.001 else { return true }
            guard let screen, mount(on: screen) else { return false }
        }
        guard abs(factor - clamped) > 0.005 else { return true }
        factor = clamped
        render(on: screen)
        return true
    }

    func rerender() {
        render(on: nil)
    }

    func remove() {
        timer?.invalidate()
        timer = nil
        window?.close()
        window = nil
        layer = nil
        factor = 1
        revealed = false
        presentsPending = 0
        renderPending = false
    }

    private func mount(on screen: NSScreen) -> Bool {
        guard let device else { return false }
        let window = NSWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle, .canJoinAllApplications, .fullScreenAuxiliary]
        window.hasShadow = false
        // Hidden until the first frame lands, so the raw EDR colour never shows.
        window.alphaValue = 0

        let metalLayer = CAMetalLayer()
        metalLayer.device = device
        metalLayer.pixelFormat = .rgba16Float
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        metalLayer.wantsExtendedDynamicRangeContent = true
        metalLayer.isOpaque = false
        metalLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
        // One uniform colour: a 1 by 1 drawable scaled to the screen costs nothing.
        metalLayer.drawableSize = CGSize(width: 1, height: 1)
        metalLayer.compositingFilter = "multiply"

        let host = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        host.layer = metalLayer
        window.contentView = host
        window.orderFrontRegardless()

        self.window = window
        self.layer = metalLayer
        revealed = false
        presentsPending = 0

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(on: nil) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            self?.reveal()
        }
        return true
    }

    private func render(on screen: NSScreen?) {
        guard let window, let layer else { return }
        if let screen, window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
            layer.frame = CGRect(origin: .zero, size: screen.frame.size)
        }
        // At most two presents in flight, so nextDrawable never blocks the
        // main thread under a drag; the counter self-resets after a second of
        // silence (display asleep mid-flight) so the keep-alive never stalls.
        if presentsPending >= 2 {
            if Date().timeIntervalSince(lastPresent) < 1 {
                renderPending = true
                return
            }
            presentsPending = 0
            lastPresent = Date()
        }
        guard let commandQueue, let drawable = layer.nextDrawable() else { return }
        presentsPending += 1
        renderPending = false
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: factor, green: factor, blue: factor, alpha: 1)
        guard let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        drawable.addPresentedHandler { [weak self] _ in
            Task { @MainActor in self?.presentLanded() }
        }
        command.present(drawable)
        if !revealed {
            command.addCompletedHandler { [weak self] _ in
                Task { @MainActor in self?.reveal() }
            }
        }
        command.commit()
    }

    private func presentLanded() {
        presentsPending = max(0, presentsPending - 1)
        lastPresent = Date()
        if renderPending { render(on: nil) }
    }

    private func reveal() {
        guard let window, !revealed else { return }
        revealed = true
        window.alphaValue = 1
    }
}
