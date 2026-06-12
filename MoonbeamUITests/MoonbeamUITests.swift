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
