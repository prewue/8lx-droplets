import AppKit
import CoreGraphics

/// The brightness keys, past the ends of the panel's range.
///
/// A session event tap sees every brightness key press. The droplet decides
/// whether a press is its own (into or inside the dim and XDR zones) or the
/// system's (anywhere in the panel's own range); an owned press is swallowed
/// so macOS neither moves the panel nor shows its HUD. The tap needs
/// Accessibility for Droppy; without it nothing is installed and the keys
/// keep working the way they always did.
@MainActor
final class BrightnessKeys {
    /// Asked for every press: up or down, fine (option and shift) or not.
    /// Returns true when the press was handled and must be swallowed.
    var handler: (@MainActor (_ up: Bool, _ fine: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var retry: Task<Void, Never>?
    private var selfReference: Unmanaged<BrightnessKeys>?

    var isArmed: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Installs the tap, or keeps trying every few seconds until it can: there
    /// is no notification for Accessibility being granted.
    func start() {
        guard tap == nil else { return }
        if !install() { scheduleRetry() }
    }

    /// Tears the tap down and installs it again, so it is the newest and
    /// therefore the first to see a press.
    func rearm() {
        guard tap != nil else {
            start()
            return
        }
        stop()
        start()
    }

    func stop() {
        retry?.cancel()
        retry = nil
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        }
        tap = nil
        source = nil
        selfReference?.release()
        selfReference = nil
    }

    private func install() -> Bool {
        guard Self.isTrusted else { return false }
        let reference = Unmanaged.passRetained(self)
        let mask = CGEventMask(1 << Self.systemDefinedEventType)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: brightnessKeyCallback,
            userInfo: reference.toOpaque()
        ) else {
            reference.release()
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        selfReference = reference
        return true
    }

    private func scheduleRetry() {
        retry?.cancel()
        retry = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                if self.install() {
                    self.retry = nil
                    return
                }
            }
        }
    }

    /// macOS switches a tap off when its callback is slow; switch it back on.
    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// NX_SYSDEFINED, the event type media and brightness keys arrive as.
    fileprivate nonisolated static let systemDefinedEventType: UInt32 = 14
    /// NX_SUBTYPE_AUX_CONTROL_BUTTONS.
    fileprivate nonisolated static let auxControlSubtype: Int16 = 8
    fileprivate nonisolated static let brightnessUpKey = 2
    fileprivate nonisolated static let brightnessDownKey = 3

    /// What a tapped event means, read where the tap runs, with nothing but values crossing to the main actor.
    fileprivate enum Press {
        case disabled
        case brightness(up: Bool, down: Bool, fine: Bool)
    }

    fileprivate nonisolated static func parse(type: CGEventType, event: CGEvent) -> Press? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return .disabled }
        guard type.rawValue == systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == auxControlSubtype else { return nil }
        let data = nsEvent.data1
        let key = (data >> 16) & 0xFF
        guard key == brightnessUpKey || key == brightnessDownKey else { return nil }
        let fine = event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift)
        return .brightness(up: key == brightnessUpKey, down: (data & 0x0100) == 0, fine: fine)
    }

    /// The tap's run loop source is on the main loop, so this runs on the main thread.
    fileprivate func handle(_ press: Press) -> Bool {
        switch press {
        case .disabled:
            reenable()
            return false
        case .brightness(let up, let down, let fine):
            // Key up is swallowed whenever key down was, so the pair stays whole.
            guard down else { return swallowedLastPress }
            swallowedLastPress = handler?(up, fine) ?? false
            return swallowedLastPress
        }
    }

    private var swallowedLastPress = false
}

private func brightnessKeyCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    guard let press = BrightnessKeys.parse(type: type, event: event) else { return Unmanaged.passUnretained(event) }
    let keys = Unmanaged<BrightnessKeys>.fromOpaque(userInfo).takeUnretainedValue()
    let swallowed = MainActor.assumeIsolated { keys.handle(press) }
    return swallowed ? nil : Unmanaged.passUnretained(event)
}
