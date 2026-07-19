import XCTest

final class BabyMontUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    @MainActor
    func testPrimaryTabsNavigateToProductionScreens() {
        XCTAssertTrue(app.staticTexts["Local-first baby monitoring"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.navigationBars["Events"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["events.history.empty"].exists || app.staticTexts["No events yet"].exists)

        app.tabBars.buttons["Rules"].tap()
        XCTAssertTrue(app.navigationBars["Rules"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.switches["rules.lowLight"].exists)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.manualCritical"].exists)

        app.tabBars.buttons["Monitor"].tap()
        XCTAssertTrue(app.navigationBars["BabyMont"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testStartMonitoringStoresEventAndUpdatesEventsTab() {
        app.buttons["button.monitor.toggle"].tap()
        XCTAssertTrue(app.staticTexts["Monitoring locally"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.staticTexts["Monitoring started"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testManualCriticalAlertAppearsInEventHistoryAndSettings() {
        app.buttons["button.test.alert"].tap()
        XCTAssertTrue(app.staticTexts["Critical alert escalated"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.staticTexts["Manual test alert"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Settings"].tap()
        app.buttons["settings.manualCritical"].tap()
        app.tabBars.buttons["Events"].tap()
        XCTAssertTrue(app.staticTexts["Manual test alert"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRulesTabExposesProductionAlertControls() {
        app.tabBars.buttons["Rules"].tap()

        XCTAssertTrue(app.sliders["rules.noise.threshold"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.sliders["rules.stillness.threshold"].exists)
        XCTAssertTrue(app.sliders["rules.humidity.low"].exists)
        XCTAssertTrue(app.sliders["rules.humidity.high"].exists)

        let lowLightToggle = app.switches["rules.lowLight"]
        for _ in 0..<3 where !lowLightToggle.exists {
            app.swipeUp()
        }
        XCTAssertTrue(lowLightToggle.waitForExistence(timeout: 3))

        let lowLightState = app.staticTexts["rules.lowLight.state"]
        XCTAssertTrue(lowLightState.waitForExistence(timeout: 3))
        XCTAssertEqual(lowLightState.label, "Low light alerts enabled")
        app.buttons["rules.lowLight.button"].tap()
        let disabledPredicate = NSPredicate(format: "label == %@", "Low light alerts disabled")
        expectation(for: disabledPredicate, evaluatedWith: lowLightState)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let measuredApp = XCUIApplication()
            measuredApp.launchArguments = ["--ui-testing"]
            measuredApp.launch()
        }
    }
}
