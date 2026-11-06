import DroppyKit
import SwiftUI

/// The droplet's page in Droppy's Settings, from Droppy's own rows.
struct BrightnesssSettings: View {
    @ObservedObject var droplet: BrightnesssDroplet

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("XDR")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Turn off XDR on battery",
                        subtitle: "Stops the dial at 100% until the Mac is plugged in.",
                        isOn: droplet.xdrOffOnBatteryBinding
                    )
                    DropletToggleRow(
                        title: "Turn off XDR when the Mac runs hot",
                        subtitle: "Comes back once the Mac has cooled down.",
                        isOn: droplet.xdrOffWhenHotBinding
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Brightness keys")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Keys go past the ends",
                        subtitle: "Brightness down keeps dimming at the minimum, and brightness up goes into XDR at the maximum.",
                        isOn: droplet.extendsKeysBinding
                    )
                    if droplet.extendsKeys {
                        DropletControlRow(title: "Accessibility") {
                            if droplet.accessibilityGranted {
                                DropletValuePill(text: droplet.keysAreExtended ? "Granted" : "Granted, arming")
                            } else {
                                Button("Allow…") { droplet.requestAccessibility() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                    DropletToggleRow(
                        title: "Show the level on the notch",
                        subtitle: "Shows the level after a key press past the ends, and says when XDR turns itself off.",
                        isOn: droplet.showsHUDBinding
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("This display")
            } content: {
                DropletSettingsCard {
                    DropletControlRow(title: "XDR ceiling") {
                        DropletValuePill(text: droplet.supportsXDR ? "\(Int(droplet.maximum))%" : "Not available")
                    }
                    DropletControlRow(title: "Panel brightness") {
                        DropletValuePill(text: droplet.engine.hardwareAvailable ? "Controlled" : "Not available")
                    }
                }
            }
        }
        // There is no notification for Accessibility being granted, so the
        // page asks while it is open, and only then.
        .task {
            while !Task.isCancelled {
                droplet.armKeysIfAllowed()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
