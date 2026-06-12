import XCTest

/// Automated version of plan task 14's manual smoke checklist:
/// seeded trip visible → three tabs with seeded content → toggle changes
/// progress by one → progress survives relaunch.
final class SmokeTests: XCTestCase {

    func testSeededTripTabsToggleAndPersistence() throws {
        let app = XCUIApplication()
        app.launch()

        // Trip list shows the seeded China trip with an x/188 progress label.
        let tripCell = app.staticTexts["2026 暑假中国行"]
        XCTAssertTrue(tripCell.waitForExistence(timeout: 10))
        let before = progressValue(in: app)

        tripCell.tap()

        // Three tabs exist.
        XCTAssertTrue(app.tabBars.buttons["Prep"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Itinerary"].exists)
        XCTAssertTrue(app.tabBars.buttons["Packing"].exists)

        // Prep tab: seeded booking row exists; toggle it.
        let astroTicket = app.staticTexts["上海天文馆门票（7/12 参观）"]
        XCTAssertTrue(astroTicket.waitForExistence(timeout: 10))
        astroTicket.tap()

        // Itinerary tab: a seeded day title is visible in the accordion.
        app.tabBars.buttons["Itinerary"].tap()
        XCTAssertTrue(app.staticTexts["抵达上海"].waitForExistence(timeout: 10))

        // Packing tab: seeded packing item and the reset button exist.
        app.tabBars.buttons["Packing"].tap()
        XCTAssertTrue(app.staticTexts["护照／证件"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Reset packing list"].exists)

        // Back to the list: overall progress moved by exactly one.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let after = progressValue(in: app)
        XCTAssertEqual(abs(after - before), 1)

        // Relaunch: the toggle was persisted (debounced save flushed).
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["2026 暑假中国行"].waitForExistence(timeout: 10))
        XCTAssertEqual(progressValue(in: app), after)
    }

    private func progressValue(in app: XCUIApplication) -> Int {
        let label = app.staticTexts
            .matching(NSPredicate(format: "label ENDSWITH '/188'"))
            .firstMatch
        XCTAssertTrue(label.waitForExistence(timeout: 10))
        return Int(label.label.split(separator: "/").first ?? "") ?? -1
    }
}
