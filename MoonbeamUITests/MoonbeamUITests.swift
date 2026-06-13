//
//  MoonbeamUITests.swift
//  MoonbeamUITests
//
//  Created by jack on 6/4/25.
//

import XCTest

final class MoonbeamUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testJetLagPlanFlow() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Jet Lag"].tap()

        let destinationField = app.textFields["City or airport code (e.g. Tokyo, LHR)"]
        XCTAssertTrue(destinationField.waitForExistence(timeout: 5))
        destinationField.tap()
        destinationField.typeText("LHR")

        attach(app, name: "1-jetlag-inputs")

        app.buttons["Generate Plan"].firstMatch.tap()

        let planTitle = app.staticTexts["Transition Plan"]
        XCTAssertTrue(planTitle.waitForExistence(timeout: 15))

        // London resolved from the IATA table, not the geocoder.
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "London")).firstMatch.waitForExistence(timeout: 5))

        attach(app, name: "2-plan-top")

        app.swipeUp()
        attach(app, name: "3-plan-bottom")
    }

    @MainActor
    func testHomeScreenSetAlarm() throws {
        addUIInterruptionMonitor(withDescription: "Permission prompts") { alert in
            for label in ["Allow", "Allow While Using App", "Allow Once", "OK"] {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }

        let app = XCUIApplication()
        app.launch()

        let setAlarm = app.buttons["Set Alarm"]
        XCTAssertTrue(setAlarm.waitForExistence(timeout: 5))
        setAlarm.tap()
        app.tap()  // nudge so the interruption monitor fires if a prompt is up

        // The button flips to "Alarm Set" for 3 seconds on success.
        XCTAssertTrue(app.staticTexts["Alarm Set"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
