import AppKit
import Combine

/// Night Shift and True Tone, through CoreBrightness's own clients, the way
/// Control Center switches them. Loaded at run time; a Mac without either
/// simply reports it unavailable and the widget hides the disc.
@MainActor
final class SystemToggles: ObservableObject {
    @Published private(set) var nightShift = false
    @Published private(set) var trueTone = false
    @Published private(set) var nightShiftAvailable = false
    @Published private(set) var trueToneAvailable = false

    private var blueLight: NSObject?
    private var trueToneClient: NSObject?
    private var isDryRun = false

    func start(dryRun: Bool) {
        isDryRun = dryRun
        if dryRun {
            nightShiftAvailable = true
            trueToneAvailable = true
            trueTone = true
            return
        }
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil else { return }
        if let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
            blueLight = type.init()
            nightShiftAvailable = true
        }
        if let type = NSClassFromString("CBTrueToneClient") as? NSObject.Type {
            let client = type.init()
            trueToneClient = client
            trueToneAvailable = Self.bool(client, "supported") && Self.bool(client, "available")
        }
        refresh()
        observe()
    }

    func stop() {
        blueLight = nil
        trueToneClient = nil
    }

    /// Each client calls this block on any change, so a switch flipped in
    /// Control Center shows on the shelf without polling.
    private func observe() {
        let onChange: @convention(block) () -> Void = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        let selector = NSSelectorFromString("setStatusNotificationBlock:")
        for client in [blueLight, trueToneClient].compactMap({ $0 }) where client.responds(to: selector) {
            typealias Call = @convention(c) (NSObject, Selector, @convention(block) () -> Void) -> Void
            unsafeBitCast(client.method(for: selector), to: Call.self)(client, selector, onChange)
        }
    }

    func refresh() {
        guard !isDryRun else { return }
        if let client = blueLight {
            var status = [UInt8](repeating: 0, count: 64)
            let selector = NSSelectorFromString("getBlueLightStatus:")
            if client.responds(to: selector) {
                typealias Call = @convention(c) (NSObject, Selector, UnsafeMutableRawPointer) -> Bool
                let ok = status.withUnsafeMutableBytes {
                    unsafeBitCast(client.method(for: selector), to: Call.self)(client, selector, $0.baseAddress!)
                }
                // The status struct starts {BOOL active, BOOL enabled, ...}.
                if ok { nightShift = status[1] != 0 }
            }
        }
        if let client = trueToneClient {
            // Availability flips with the lid: clamshell hides True Tone.
            let available = Self.bool(client, "supported") && Self.bool(client, "available")
            if trueToneAvailable != available { trueToneAvailable = available }
            if available { trueTone = Self.bool(client, "enabled") }
        }
    }

    func setNightShift(_ on: Bool) {
        nightShift = on
        guard let client = blueLight else { return }
        Self.set(client, "setEnabled:", on)
    }

    func setTrueTone(_ on: Bool) {
        trueTone = on
        guard let client = trueToneClient else { return }
        Self.set(client, "setEnabled:", on)
    }

    private static func bool(_ object: NSObject, _ name: String) -> Bool {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return false }
        typealias Call = @convention(c) (NSObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: selector), to: Call.self)(object, selector)
    }

    private static func set(_ object: NSObject, _ name: String, _ value: Bool) {
        let selector = NSSelectorFromString(name)
        guard object.responds(to: selector) else { return }
        typealias Call = @convention(c) (NSObject, Selector, Bool) -> Void
        unsafeBitCast(object.method(for: selector), to: Call.self)(object, selector, value)
    }
}
