import Foundation
import IOKit.ps

/// Watches what XDR costs: the battery and the Mac's temperature.
@MainActor
final class PowerGuard {
    private(set) var isOnBattery = false
    private(set) var isHot = false
    var onChange: (@MainActor () -> Void)?

    private var powerSource: CFRunLoopSource?
    private var thermalObserver: NSObjectProtocol?

    func start(dryRun: Bool) {
        guard !dryRun else { return }
        refresh(announce: false)
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let guardian = Unmanaged<PowerGuard>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in guardian.refresh(announce: true) }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        }
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh(announce: true) }
        }
    }

    func stop() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            self.powerSource = nil
        }
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }
    }

    private func refresh(announce: Bool) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String?
        let battery = providing == kIOPMBatteryPowerKey
        let state = ProcessInfo.processInfo.thermalState
        let hot = state == .serious || state == .critical
        let changed = battery != isOnBattery || hot != isHot
        isOnBattery = battery
        isHot = hot
        if changed, announce { onChange?() }
    }
}
