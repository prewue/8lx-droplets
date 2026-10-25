import DroppyKit
import DroppyKitHarness
import UnaNota

@main
struct UnaNotaHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { UnaNotaDroplet() }
}
