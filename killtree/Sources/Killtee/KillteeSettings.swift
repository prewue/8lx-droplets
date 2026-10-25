import DroppyKit
import SwiftUI

/// The droplet's page in Droppy's Settings, from Droppy's own rows.
struct KillteeSettings: View {
    @ObservedObject var droplet: KillteeDroplet

    var body: some View {
        DropletSettingsPane {
            DropletSettingsSection {
                settingsSectionHeader("Closing")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Keep closed after a restart",
                        subtitle: "The app's launchd jobs are disabled too, so they do not start again at the next login.",
                        isOn: droplet.persistsBinding
                    )
                    DropletToggleRow(
                        title: "Bring them back when the app opens",
                        subtitle: "Opening any app of a closed vendor lets its background services start again. Off, they wait for Restore.",
                        isOn: droplet.autoRestoreBinding
                    )
                    DropletToggleRow(
                        title: "Close again if they come back",
                        subtitle: "Some helpers are started by other helpers, not by launchd. K*llTree closes them again while the vendor is kept closed.",
                        isOn: droplet.guardsBinding
                    )
                    DropletToggleRow(
                        title: "Also stop system services",
                        subtitle: "Updaters and licensing services run as root. Stopping them asks for an administrator password each time.",
                        isOn: droplet.includesSystemBinding
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Shelf")
            } content: {
                DropletSettingsCard {
                    DropletToggleRow(
                        title: "Show every app",
                        subtitle: "Off, the list only shows apps that leave something running in the background.",
                        isOn: droplet.showsAllBinding
                    )
                    DropletToggleRow(
                        title: "Show the result on the notch",
                        subtitle: "A strip with what was closed and the memory it held.",
                        isOn: droplet.showsHUDBinding
                    )
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Kept closed")
            } content: {
                DropletSettingsCard {
                    if droplet.state.closed.isEmpty {
                        DropletControlRow(title: "Nothing is kept closed") {
                            EmptyView()
                        }
                    } else {
                        ForEach(droplet.state.closed) { closed in
                            DropletControlRow(title: closed.name) {
                                Button("Restore") { droplet.restore(closed.id) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        DropletControlRow(title: "Everything") {
                            Button("Restore all") { droplet.restoreAll() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if droplet.offersDemo {
                DropletSettingsSection {
                    settingsSectionHeader("Testing")
                } content: {
                    DropletSettingsCard {
                        DropletToggleRow(
                            title: "Demo data",
                            subtitle: "A made-up Mac to try the list on: open apps, leftovers, terminals and servers. Closing and restoring only change the demo; nothing real is scanned, ended or saved. Only in Droppy Playground.",
                            isOn: droplet.demoBinding
                        )
                        if droplet.isDemo {
                            DropletControlRow(title: "Start the demo over") {
                                Button("Reset") { droplet.resetDemo() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }

            DropletSettingsSection {
                settingsSectionHeader("Journal")
            } content: {
                DropletSettingsCard {
                    if droplet.state.journal.isEmpty {
                        DropletControlRow(title: "Nothing closed yet") {
                            EmptyView()
                        }
                    } else {
                        DropletStackedRow(title: "Recent") {
                            VStack(alignment: .leading, spacing: DroppySpacing.sm) {
                                ForEach(droplet.state.journal.prefix(12)) { entry in
                                    JournalLine(entry: entry)
                                }
                            }
                        }
                        DropletControlRow(title: "Journal") {
                            Button("Clear") { droplet.clearJournal() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }
}

private struct JournalLine: View {
    let entry: JournalEntry

    private var tint: Color {
        switch entry.kind {
        case .closed: return KillteeDroplet.closeTint
        case .refused: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DroppySpacing.sm) {
            Image(systemName: entry.symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
