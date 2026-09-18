import DroppyKit
import DroppyKitHarness
import FreelanceTracker

@main
struct FreelanceTrackerHarness: DropletHarnessApp {
    static func makeDroplet() -> any Droplet { FreelanceTrackerDroplet() }
}
