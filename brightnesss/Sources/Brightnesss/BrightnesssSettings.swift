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
                        subtitle: "Brightness past 100% drains the battery fast. The dial stops at 100% until the Mac is plugged in again.",
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
                        subtitle: "At the minimum, brightness down keeps dimming; at the maximum, brightness up goes into XDR. Inside the panel's own range the keys work as always. Needs Accessibility for Droppy.",
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
                        subtitle: "A strip with the level after a key press past the ends, and a word when XDR turns itself off.",
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
    }
}
