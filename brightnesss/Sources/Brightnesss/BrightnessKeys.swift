import AppKit
import CoreGraphics

/// The rule for a brightness key press, free of AppKit: a press is ours when it
/// goes into or moves inside the dim and XDR zones. Anywhere in the panel's own
/// range it is the system's.
enum BrightnessKeyRule {
    static func isOurs(level: Double, limit: Double, up: Bool) -> Bool {
        let outsidePanel = level < 0 || level > 100
        let crossesFloor = !up && level <= 0
        let crossesCeiling = up && level >= 100 && limit > 100
        return outsidePanel || crossesFloor || crossesCeiling
    }

    /// The level to decide from. Inside the panel's range the stored one can be
    /// a poll behind a held key, so the panel itself says where it is; outside
    /// it the panel says nothing, and the stored level is the level.
    static func current(stored: Double, panel: Float?) -> Double {
        guard stored >= 0, stored <= 100, let panel else { return stored }
        return BoostMath.level(forPanel: panel)
    }
}

/// The brightness keys, past the ends of the panel's range.
///
/// A session event tap sees every brightness key press and decides at once
/// whether it is ours; an owned press is swallowed so macOS neither moves the
/// panel nor shows its HUD. The tap needs Accessibility for Droppy; without it
/// nothing is installed and the keys keep working the way they always did.
@MainActor
final class BrightnessKeys {
    /// Told about every press, after the tap has decided: up or down, fine
    /// (option and shift) or not, whether it was swallowed as ours, and the
    /// level the decision was made from. `nil` for a held key that is already
    /// ours: the droplet's own level is ahead of a panel still gliding to it.
    var handler: (@MainActor (_ up: Bool, _ fine: Bool, _ isOurs: Bool, _ from: Double?) -> Void)?
    /// The key came up.
    var onRelease: (@MainActor () -> Void)?

    private var tap: BrightnessKeyTap?
    private let state = BrightnessKeyState()

    var isArmed: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// What the tap decides from, on its own thread. Every change of the level
    /// or the ceiling lands here.
    func update(level: Double, limit: Double, display: CGDirectDisplayID) {
        state.set(level: level, limit: limit, display: display)
    }

    /// Installs the tap if Accessibility allows it. There is no notification
    /// for it being granted: the settings page and the shelf opening ask again.
    func start() {
        guard tap == nil, Self.isTrusted else { return }
        let forward: @Sendable (Bool, Bool, Bool, Double?) -> Void = { [weak self] up, fine, isOurs, from in
            Task { @MainActor in self?.handler?(up, fine, isOurs, from) }
        }
        let release: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.onRelease?() }
        }
        let tap = BrightnessKeyTap(state: state, forward: forward, release: release)
        if tap.start() { self.tap = tap }
    }

    /// Tears the tap down and installs it again, so it is the newest and
    /// therefore the first to see a press.
    func rearm() {
        stop()
        start()
    }

    func stop() {
        tap?.stop()
        tap = nil
    }
}

/// The level and the ceiling, readable from the tap's thread without waiting
/// for whatever Droppy is drawing.
private final class BrightnessKeyState: @unchecked Sendable {
    private let lock = NSLock()
    private var level: Double = 100
    private var limit: Double = 100
    private var display: CGDirectDisplayID = 0

    func set(level: Double, limit: Double, display: CGDirectDisplayID) {
        lock.withLock {
            self.level = level
            self.limit = limit
            self.display = display
        }
    }

    /// Reads the panel outside the lock, on the tap's own thread: this is what
    /// lets a held key be caught at the floor instead of switching it off.
    func decide(up: Bool) -> (isOurs: Bool, from: Double) {
        let (stored, limit, display) = lock.withLock { (level, self.limit, self.display) }
        let from = BrightnessKeyRule.current(stored: stored, panel: PanelBrightness.read(display))
        return (BrightnessKeyRule.isOurs(level: from, limit: limit, up: up), from)
    }
}

/// The event tap, on a thread and a run loop of its own: on the main run loop
/// every press would wait for Droppy's drawing, and macOS disables a tap that
/// answers too slowly.
private final class BrightnessKeyTap: @unchecked Sendable {
    private let lock = NSLock()
    private let state: BrightnessKeyState
    private let forward: @Sendable (Bool, Bool, Bool, Double?) -> Void
    private let release: @Sendable () -> Void
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var isStopped = false
    /// Only the tap's thread touches these. A held key stays ours once it is:
    /// Droppy ignores repeats of a press whose start it never saw, and macOS
    /// then takes them and shows its own HUD. Key up follows the first press,
    /// so whoever saw the start also sees the end.
    private var swallowedLastPress = false
    private var swallowedFirstPress = false

    init(
        state: BrightnessKeyState,
        forward: @escaping @Sendable (Bool, Bool, Bool, Double?) -> Void,
        release: @escaping @Sendable () -> Void
    ) {
        self.state = state
        self.forward = forward
        self.release = release
    }

    /// Creates the tap, so its failure is known here, and runs it on its thread.
    func start() -> Bool {
        let mask = CGEventMask(1 << Self.systemDefinedEventType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: brightnessKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            return false
        }
        self.tap = tap
        self.source = source
        let thread = Thread { [self] in run(source: source, tap: tap) }
        thread.name = "Brightnesss key tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    private func run(source: CFRunLoopSource, tap: CFMachPort) {
        lock.lock()
        // stop() may have run before this thread got here.
        guard !isStopped else {
            lock.unlock()
            return
        }
        runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.unlock()
        CFRunLoopRun() // Returns once stop() has stopped the loop.
    }

    /// Safe before, during and after the thread starts. The callback only runs
    /// on the thread's loop, which has stopped by the time the tap is released.
    func stop() {
        lock.lock()
        isStopped = true
        let tap = self.tap, source = self.source, runLoop = self.runLoop
        self.tap = nil
        self.source = nil
        self.runLoop = nil
        lock.unlock()

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopSourceInvalidate(source) }
        if let tap { CFMachPortInvalidate(tap) }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    /// NX_SYSDEFINED, the event type media and brightness keys arrive as.
    fileprivate static let systemDefinedEventType: UInt32 = 14
    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS.
    private static let auxControlSubtype: Int16 = 8
    private static let brightnessUpKey = 2
    private static let brightnessDownKey = 3

    /// Runs on the tap's thread. Returns true to swallow the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.withLock {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            }
            return false
        }
        guard type.rawValue == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlSubtype else { return false }
        let data = nsEvent.data1
        let key = (data >> 16) & 0xFF
        guard key == Self.brightnessUpKey || key == Self.brightnessDownKey else { return false }
        guard (data & 0x0100) == 0 else {
            release()
            return swallowedFirstPress
        }
        let up = key == Self.brightnessUpKey
        let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
        let isRepeat = (data & 0x1) != 0
        if isRepeat, swallowedLastPress {
            forward(up, fine, true, nil)
            return true
        }
        let decision = state.decide(up: up)
        if !isRepeat { swallowedFirstPress = decision.isOurs }
        swallowedLastPress = decision.isOurs
        forward(up, fine, decision.isOurs, decision.from)
        return decision.isOurs
    }
}

private func brightnessKeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<BrightnessKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
}
