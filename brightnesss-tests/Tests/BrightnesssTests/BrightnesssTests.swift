import DroppyKit
import DroppyKitHarness
import XCTest
@testable import Brightnesss

final class MathTests: XCTestCase {
    func testPanelRoundTrip() {
        for level in 0...100 {
            XCTAssertEqual(BoostMath.level(forPanel: BoostMath.panel(for: Double(level))), Double(level))
        }
        XCTAssertEqual(BoostMath.panel(for: 0), BoostMath.panelFloor)
        XCTAssertEqual(BoostMath.panel(for: 100), 1)
        XCTAssertEqual(BoostMath.level(forPanel: 0), 0)
    }

    func testCeiling() {
        XCTAssertEqual(BoostMath.maximum(potentialHeadroom: 1.05), 100)
        XCTAssertEqual(BoostMath.maximum(potentialHeadroom: 1.6), 160)
        XCTAssertEqual(BoostMath.maximum(potentialHeadroom: 16), 200)
    }

    func testFactors() {
        XCTAssertEqual(BoostMath.overlayFactor(level: 100, maximum: 200, currentHeadroom: 2, potentialHeadroom: 2), 1)
        XCTAssertEqual(BoostMath.overlayFactor(level: 150, maximum: 200, currentHeadroom: 1, potentialHeadroom: 2), BoostMath.pendingFactor)
        XCTAssertEqual(BoostMath.overlayFactor(level: 200, maximum: 200, currentHeadroom: 4, potentialHeadroom: 16), 4, accuracy: 0.001)
        XCTAssertEqual(BoostMath.dimFactor(level: -100), BoostMath.dimFloor, accuracy: 0.0001)
    }
}

final class KeyRuleTests: XCTestCase {
    func testInsideThePanelTheKeysAreTheSystems() {
        XCTAssertFalse(BrightnessKeyRule.isOurs(level: 50, limit: 200, up: true))
        XCTAssertFalse(BrightnessKeyRule.isOurs(level: 50, limit: 200, up: false))
        XCTAssertFalse(BrightnessKeyRule.isOurs(level: 0, limit: 200, up: true))
        XCTAssertFalse(BrightnessKeyRule.isOurs(level: 100, limit: 200, up: false))
    }

    func testPastTheEndsTheyAreOurs() {
        XCTAssertTrue(BrightnessKeyRule.isOurs(level: 0, limit: 200, up: false))
        XCTAssertTrue(BrightnessKeyRule.isOurs(level: 100, limit: 200, up: true))
        XCTAssertTrue(BrightnessKeyRule.isOurs(level: -30, limit: 200, up: true))
        XCTAssertTrue(BrightnessKeyRule.isOurs(level: 130, limit: 200, up: false))
    }

    /// The bug: a held key outran the 300 ms poll and switched the backlight off.
    func testAHeldKeyIsCaughtAtTheFloorEvenIfTheStoredLevelIsBehind() {
        let from = BrightnessKeyRule.current(stored: 12, panel: BoostMath.panelFloor)
        XCTAssertEqual(from, 0)
        XCTAssertTrue(BrightnessKeyRule.isOurs(level: from, limit: 200, up: false))
    }

    func testAnOffPanelCountsAsTheFloor() {
        XCTAssertEqual(BrightnessKeyRule.current(stored: 5, panel: 0), 0)
        XCTAssertTrue(BoostMath.panelIsOff(0))
        XCTAssertTrue(BoostMath.panelIsOff(0.0035), "on its way there, still gliding")
        XCTAssertFalse(BoostMath.panelIsOff(BoostMath.panelFloor))
    }

    func testPastTheEndsThePanelDoesNotDecide() {
        XCTAssertEqual(BrightnessKeyRule.current(stored: -30, panel: BoostMath.panelFloor), -30)
        XCTAssertEqual(BrightnessKeyRule.current(stored: 130, panel: 1), 130)
        XCTAssertEqual(BrightnessKeyRule.current(stored: 40, panel: nil), 40)
    }

    func testABlockedCeilingLeavesThePressToTheSystem() {
        XCTAssertFalse(BrightnessKeyRule.isOurs(level: 100, limit: 100, up: true))
    }
}

final class RestoreLimitTests: XCTestCase {
    func testTwoThingsFightingCannotStrobeTheScreen() {
        var limit = BacklightRestoreLimit()
        let start = Date()
        let allowed = (0..<20).filter { limit.allow(at: start.addingTimeInterval(Double($0) * 0.1)) }
        XCTAssertEqual(allowed.count, BacklightRestoreLimit.count)
        XCTAssertTrue(limit.allow(at: start.addingTimeInterval(BacklightRestoreLimit.window + 1)), "the screen comes back once it is over")
    }
}

@MainActor
final class DropletTests: XCTestCase {
    private func make() throws -> BrightnesssDroplet {
        let droplet = BrightnesssDroplet()
        try droplet.activate(host: .harness(dropletID: BrightnesssDroplet.id, recorder: HarnessRecorder()))
        XCTAssertTrue(droplet.engine.isDryRun, "never the real panel")
        return droplet
    }

    func testClampsAndZones() throws {
        let droplet = try make()
        droplet.setLevel(500)
        XCTAssertEqual(droplet.level, 200)
        droplet.setLevel(-500)
        XCTAssertEqual(droplet.level, -100)
        droplet.setLevel(50)
        droplet.toggleXDR()
        XCTAssertEqual(droplet.level, 200)
        droplet.toggleXDR()
        XCTAssertEqual(droplet.level, 100)
    }

    func testTheWelcomeScreenDoesNotStretchARow() throws {
        let droplet = try make()
        XCTAssertEqual(droplet.screen, .welcome)
        let solo = droplet.widgetHeight
        droplet.setPaired(true)
        XCTAssertLessThan(droplet.widgetHeight, solo)
        droplet.setPaired(false)
        XCTAssertEqual(droplet.widgetHeight, solo)
    }

    func testNothingRunsAfterDeactivate() throws {
        let droplet = try make()
        droplet.widgetAppeared(isPaired: false)
        droplet.deactivate()
        XCTAssertFalse(droplet.keys.isArmed)
        droplet.requestAccessibility()
        XCTAssertFalse(droplet.keys.isArmed)
    }

    func testManifestAsksOnlyForWhatItUses() throws {
        let manifest = try String(contentsOfFile: "../brightnesss/droplet.json", encoding: .utf8)
        XCTAssertFalse(manifest.contains("shelf-write"))
    }
}
