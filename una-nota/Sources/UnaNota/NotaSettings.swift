import DroppyKit
import SwiftUI

struct UnaNotaSettings: View {
    @ObservedObject var droplet: UnaNotaDroplet

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Reminders")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Show a strip when a reminder is due",
                        subtitle: "On the day, a strip with the reminder shows on the notch once.",
                        isOn: droplet.showsDueStripBinding
                    )
                    DropletToggleRow(
                        title: "Keep completed reminders",
                        subtitle: "Off, a reminder leaves the list the moment it is done.",
                        isOn: droplet.keepsCompletedBinding
                    )
                }
            }
        }
    }
}
