import XCTest

/// Walks the seeded trip and captures App Store screenshots as keepAlways
/// attachments. Extract from the result bundle with:
///   xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
final class ScreenshotTests: XCTestCase {

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // Dismiss the notification-permission alert if reminders trigger it.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }

        let tripCell = app.staticTexts["2026 暑假中国行"]
        XCTAssertTrue(tripCell.waitForExistence(timeout: 10))
        snap("1-trip-list")

        tripCell.tap()
        XCTAssertTrue(tabButton(app, "Prep").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["上海天文馆门票（7/12 参观）"].waitForExistence(timeout: 10))
        snap("2-prep")

        tabButton(app, "Itinerary").tap()
        XCTAssertTrue(app.staticTexts["抵达上海"].waitForExistence(timeout: 10))
        snap("3-itinerary")

        tabButton(app, "Packing").tap()
        XCTAssertTrue(app.staticTexts["护照／证件"].waitForExistence(timeout: 10))
        snap("4-packing")
    }

    /// iPhone renders TabView tabs in a bottom tabBar; iPad (iOS 18+) renders
    /// them outside any tabBar element, so fall back to a plain button query.
    private func tabButton(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let inTabBar = app.tabBars.buttons[label]
        return inTabBar.exists ? inTabBar : app.buttons[label].firstMatch
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
