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

        let createAlarm = app.buttons["Create Alarm"]
        let deleteAlarm = app.buttons["Delete Alarm"]
        if deleteAlarm.exists { deleteAlarm.tap() }
        XCTAssertTrue(createAlarm.waitForExistence(timeout: 5))
        createAlarm.tap()
        app.tap()  // allow the permission interruption monitor to run

        XCTAssertTrue(deleteAlarm.waitForExistence(timeout: 8))
        app.terminate()
        app.launch()
        XCTAssertTrue(deleteAlarm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Other alarms created in iOS are not visible here"].exists)
        deleteAlarm.tap()
        XCTAssertTrue(createAlarm.waitForExistence(timeout: 5))
        XCTAssertFalse(deleteAlarm.exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    func testExactMinutePickerAndTimeLocks() throws {
        let app = XCUIApplication()
        app.launch()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            let deny = app.alerts.buttons["Don’t Allow"]
            if deny.exists { deny.tap() }
        }

        let bedtime = app.buttons["Edit bedtime"]
        XCTAssertTrue(bedtime.waitForExistence(timeout: 5))
        bedtime.tap()
        let minuteWheel = app.pickerWheels.element(boundBy: 1)
        XCTAssertTrue(minuteWheel.waitForExistence(timeout: 5))
        minuteWheel.adjust(toPickerWheelValue: "37")
        app.buttons["Done"].tap()
        XCTAssertTrue((bedtime.value as? String)?.contains(":37") == true)

        let bedtimeLock = app.buttons["Fix bedtime"]
        XCTAssertTrue(bedtimeLock.isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        bedtimeLock.tap()
        XCTAssertEqual(bedtimeLock.value as? String, "Locked")
        let alarmLock = app.buttons["Fix alarm"]
        alarmLock.tap()
        XCTAssertEqual(alarmLock.value as? String, "Locked")
        XCTAssertTrue(app.staticTexts["These times don’t fit whole REM cycles, including your fall-asleep buffer."]
            .waitForExistence(timeout: 3))
        XCTAssertTrue((bedtime.value as? String)?.contains(":37") == true)
        XCTAssertTrue(app.buttons["Sleep Now"].isHittable)
        XCTAssertTrue(app.buttons["Create Alarm"].isHittable || app.buttons["Delete Alarm"].isHittable)
        attach(app, name: "exact-times-locked-with-warning")
    }

    @MainActor
    func testFixedHandlesRemainDirectlyDraggable() throws {
        let app = XCUIApplication()
        app.launch()
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            let deny = app.alerts.buttons["Don’t Allow"]
            if deny.exists { deny.tap() }
        }
        app.buttons["Fix bedtime"].tap()
        app.buttons["Fix alarm"].tap()
        let bedtime = app.buttons["Edit bedtime"]
        let alarm = app.buttons["Edit alarm time"]
        let originalBedtime = bedtime.value as? String
        let originalAlarm = alarm.value as? String

        func dragTime(from minutes: Int, to targetMinutes: Int) {
            let dial = app.otherElements["sleepDial"]
            let radius = min(dial.frame.width, dial.frame.height) / 2 - 9
            let center = dial.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            func point(_ time: Int) -> XCUICoordinate {
                let angle = Double(time) / 1440 * 2 * .pi - .pi / 2
                return center.withOffset(CGVector(dx: cos(angle) * radius, dy: sin(angle) * radius))
            }
            point(minutes).press(forDuration: 0.15, thenDragTo: point(targetMinutes))
        }

        dragTime(from: 22 * 60 + 30, to: 21 * 60 + 30)
        let changedBedtime = bedtime.value as? String
        XCTAssertNotEqual(changedBedtime, originalBedtime)
        XCTAssertEqual(alarm.value as? String, originalAlarm)
        dragTime(from: 7 * 60 + 45, to: 6 * 60 + 45)
        XCTAssertNotEqual(alarm.value as? String, originalAlarm)
        XCTAssertEqual(bedtime.value as? String, changedBedtime)
        XCTAssertEqual(app.buttons["Fix bedtime"].value as? String, "Locked")
        XCTAssertEqual(app.buttons["Fix alarm"].value as? String, "Locked")
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
