import AppKit
import XCTest
@testable import FreelanceTracker

final class TrackerClockTests: XCTestCase {
    func testFullClock() {
        XCTAssertEqual(TrackerClock.full(0), "00:00")
        XCTAssertEqual(TrackerClock.full(59.9), "00:59")
        XCTAssertEqual(TrackerClock.full(3_599), "59:59")
        XCTAssertEqual(TrackerClock.full(3_661), "1:01:01")
    }

    func testCompactClock() {
        XCTAssertEqual(TrackerClock.compact(59), "00:59")
        XCTAssertEqual(TrackerClock.compact(3_661), "1:01")
    }

    func testBriefDuration() {
        XCTAssertEqual(TrackerClock.brief(59), "0m")
        XCTAssertEqual(TrackerClock.brief(3_660), "1h 1m")
    }

    func testParseAcceptsEveryWrittenForm() {
        XCTAssertEqual(TrackerClock.parse("1:30"), 5_400)
        XCTAssertEqual(TrackerClock.parse("1:30:15"), 5_415)
        XCTAssertEqual(TrackerClock.parse("90"), 5_400)
        XCTAssertEqual(TrackerClock.parse("1.5"), 5_400)
        XCTAssertEqual(TrackerClock.parse("1,5"), 5_400)
        XCTAssertEqual(TrackerClock.parse("1h 30m"), 5_400)
        XCTAssertEqual(TrackerClock.parse(" 45m "), 2_700)
    }

    func testParseRejectsWhatIsNotADuration() {
        XCTAssertNil(TrackerClock.parse(""))
        XCTAssertNil(TrackerClock.parse("soon"))
        XCTAssertNil(TrackerClock.parse("1:xx"))
        XCTAssertNil(TrackerClock.parse("-5"))
        XCTAssertNil(TrackerClock.parse("h"))
    }
}

final class TrackerCurrencyTests: XCTestCase {
    func testDollarAmounts() {
        let usd = TrackerCurrency.named("USD")
        XCTAssertEqual(usd.format(1_234.5), "$1,234.50")
        XCTAssertEqual(usd.format(1_234.4, compact: true), "$1234")
        XCTAssertEqual(usd.format(12.3, compact: true), "$12.30")
    }

    func testWholeUnitCurrenciesDropCents() {
        XCTAssertEqual(TrackerCurrency.named("JPY").format(1_500), "¥1,500")
    }

    func testSuffixCurrencies() {
        XCTAssertEqual(TrackerCurrency.named("PLN").format(12.5), "12.50 zł")
        XCTAssertEqual(TrackerCurrency.named("CHF").formatRate(252), "252 CHF/h")
    }

    func testRatesAndPlainAmounts() {
        let usd = TrackerCurrency.named("USD")
        XCTAssertEqual(usd.formatRate(50), "$50/h")
        XCTAssertEqual(usd.formatRate(52.5), "$52.50/h")
        XCTAssertEqual(usd.formatAmount(132.45), "$132.45")
    }

    func testUnknownCodeFallsBackToTheDollar() {
        XCTAssertEqual(TrackerCurrency.named("XYZ"), TrackerCurrency.usd)
    }
}

final class ProjectTests: XCTestCase {
    func testEarningsFollowTheRate() {
        let project = Project(name: "Acme", rate: 60, currencyCode: "USD")
        XCTAssertEqual(project.earnings(for: 5_400), 90, accuracy: 0.000_1)
        XCTAssertEqual(project.formattedEarnings(for: 5_400), "$90.00")
    }

    func testProjectSavedBeforeColoursAndIconsStillLoads() throws {
        let json = """
        {"id":"D346D119-A5A0-48E1-9A1B-7E8D524D33B9","name":"Old","rate":40,"currencyCode":"EUR","createdAt":0}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(project.name, "Old")
        XCTAssertEqual(project.color, .cyan)
        XCTAssertEqual(project.icon, .briefcase)
        XCTAssertNil(project.currentSessionID)
    }

    func testUnknownColourOrIconDoesNotLoseTheProject() throws {
        let json = """
        {"id":"D346D119-A5A0-48E1-9A1B-7E8D524D33B9","name":"Future","rate":40,"currencyCode":"EUR","createdAt":0,"color":"ultraviolet","icon":"rocket"}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        XCTAssertEqual(project.color, .cyan)
        XCTAssertEqual(project.icon, .briefcase)
    }

    func testColourAndIconSurviveARoundTrip() throws {
        let original = Project(name: "Blog", rate: 35, currencyCode: "GBP", color: .orange, icon: .pencil)
        let copy = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(copy, original)
    }

    func testSuggestedColourWalksThePalette() {
        XCTAssertEqual(ProjectColor.suggested(forProjectNumber: 1), .cyan)
        XCTAssertEqual(ProjectColor.suggested(forProjectNumber: 2), .blue)
        XCTAssertEqual(ProjectColor.suggested(forProjectNumber: ProjectColor.allCases.count + 1), .cyan)
    }

    func testEveryIconHasASymbol() {
        for icon in ProjectIcon.allCases {
            XCTAssertFalse(icon.symbol.isEmpty, "\(icon)")
            XCTAssertNotNil(NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil), icon.symbol)
        }
    }
}

final class WorkSessionTests: XCTestCase {
    func testPausedSessionKeepsItsBankedTime() {
        let session = WorkSession(projectID: UUID(), name: "Paused", accumulated: 600)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(session.duration(at: Date()), 600)
    }

    func testRunningSessionAddsTheOpenStretch() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = WorkSession(projectID: UUID(), name: "Running", accumulated: 60, activeSince: start)
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.duration(at: start.addingTimeInterval(90)), 150)
        XCTAssertEqual(session.duration(at: start.addingTimeInterval(-30)), 60)
    }
}

final class TrackerCSVTests: XCTestCase {
    private func rows(_ csv: String) -> [String] {
        csv.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func testHeaderAndOldestFirst() {
        let project = Project(name: "Acme", rate: 60, currencyCode: "USD")
        let early = WorkSession(projectID: project.id, name: "First", createdAt: Date(timeIntervalSince1970: 1_000), accumulated: 5_400)
        let late = WorkSession(projectID: project.id, name: "Second", createdAt: Date(timeIntervalSince1970: 90_000), accumulated: 1_800)
        let lines = rows(TrackerCSV.render(projects: [project], sessions: [late, early], now: Date()))
        XCTAssertEqual(lines.first, TrackerCSV.header)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("Acme,First,"))
        XCTAssertTrue(lines[2].hasPrefix("Acme,Second,"))
        XCTAssertTrue(lines[1].hasSuffix(",1:30:00,1.50,60,USD,90.00,Done"), lines[1])
    }

    func testDayFollowsTheUsersTimeZone() {
        // 22:30 in London is already the next morning in Moscow.
        let lateEvening = Date(timeIntervalSince1970: 1_767_306_600)
        XCTAssertEqual(TrackerCSV.day(lateEvening, in: TimeZone(identifier: "UTC")!), "2026-01-01")
        XCTAssertEqual(TrackerCSV.day(lateEvening, in: TimeZone(identifier: "Europe/Moscow")!), "2026-01-02")
    }

    func testFieldsWithCommasAndQuotesAreQuoted() {
        let project = Project(name: "Acme, Inc", rate: 10, currencyCode: "EUR")
        let session = WorkSession(projectID: project.id, name: "Say \"hi\"", accumulated: 3_600)
        let line = rows(TrackerCSV.render(projects: [project], sessions: [session], now: Date()))[1]
        XCTAssertTrue(line.hasPrefix("\"Acme, Inc\",\"Say \"\"hi\"\"\","), line)
    }

    func testRunningSessionIsMarkedAndSessionsOfOtherProjectsAreLeftOut() {
        let project = Project(name: "Acme", rate: 60, currencyCode: "USD")
        let running = WorkSession(projectID: project.id, name: "Now", accumulated: 0, activeSince: Date().addingTimeInterval(-60))
        let stray = WorkSession(projectID: UUID(), name: "Elsewhere", accumulated: 60)
        let lines = rows(TrackerCSV.render(projects: [project], sessions: [running, stray], now: Date()))
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].hasSuffix(",Running"), lines[1])
    }
}
