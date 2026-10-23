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
    func testAddingAndRemovingConnectingFlights() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Jet Lag"].tap()

        func addFlight() {
            let button = app.buttons["addFlight"]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            for _ in 0..<4 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable)
            button.tap()
        }

        addFlight()
        XCTAssertTrue(app.textFields["flightNumber-1"].waitForExistence(timeout: 3))
        addFlight()
        XCTAssertTrue(app.textFields["flightNumber-2"].waitForExistence(timeout: 3))
        addFlight()
        XCTAssertTrue(app.textFields["flightNumber-3"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["addFlight"].exists)
        attach(app, name: "three-flight-entries")

        let removeSecond = app.buttons["Remove flight 2"]
        for _ in 0..<4 where !removeSecond.isHittable { app.swipeDown() }
        XCTAssertTrue(removeSecond.isHittable)
        removeSecond.tap()
        XCTAssertFalse(app.textFields["flightNumber-3"].exists)
        addFlight()
        XCTAssertTrue(app.textFields["flightNumber-3"].waitForExistence(timeout: 3))
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
    func testSleepNowUsesCurrentMinuteWithAnExactAlarm() throws {
        let app = XCUIApplication()
        app.launch()
        let sleepNow = app.buttons["Sleep Now"]
        XCTAssertTrue(sleepNow.waitForExistence(timeout: 5))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        for fixedAlarm in [false, true] {
            if fixedAlarm { app.buttons["Fix Alarm"].tap() }
            let alarmBefore = app.buttons["Edit alarm time"].value as? String
            let before = formatter.string(from: Date())
            sleepNow.tap()
            let after = formatter.string(from: Date())
            let bedtime = app.buttons["Edit bedtime"].value as? String
            XCTAssertTrue(bedtime == before || bedtime == after)
            if fixedAlarm {
                XCTAssertEqual(app.buttons["Edit alarm time"].value as? String, alarmBefore)
            }
        }
    }

    @MainActor
    func testWakeByFloatsAlarmBeforeDeadline() throws {
        let app = XCUIApplication()
        app.launch()
        let bedtime = app.buttons["Edit bedtime"]
        XCTAssertTrue(bedtime.waitForExistence(timeout: 5))
        bedtime.tap()
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "37")
        app.buttons["Done"].tap()
        let alarm = app.buttons["Edit alarm time"]
        alarm.tap()
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "13")
        app.buttons["Done"].tap()
        app.buttons["Fix Alarm"].tap()
        let wakeBy = app.buttons["Wake By Mode"]
        XCTAssertTrue(wakeBy.isHittable)
        wakeBy.tap()
        XCTAssertEqual(app.buttons["Fix Alarm"].value as? String, "Unlocked")
        XCTAssertTrue((wakeBy.value as? String)?.contains("7:13") == true)
        let wakeByTime = app.buttons["Edit wake by time"]
        XCTAssertTrue((wakeByTime.value as? String)?.contains("7:13") == true)
        XCTAssertTrue(app.staticTexts["WAKE BY"].exists)
        XCTAssertTrue((app.otherElements["Wake up"].value as? String)?.contains("7:13") == true)
        XCTAssertTrue((app.otherElements["Actual alarm"].value as? String)?.contains("6:22") == true)
        XCTAssertTrue((bedtime.value as? String)?.contains("10:37") == true)
        attach(app, name: "wake-by-deadline")
        wakeByTime.tap()
        XCTAssertTrue(app.navigationBars["Set Wake By Time"].waitForExistence(timeout: 3))
        XCTAssertTrue((app.pickerWheels.element(boundBy: 1).value as? String)?.hasPrefix("13") == true)
        app.pickerWheels.element(boundBy: 1).adjust(toPickerWheelValue: "43")
        app.buttons["Done"].tap()
        XCTAssertTrue((wakeByTime.value as? String)?.contains("7:43") == true)
        XCTAssertTrue((app.otherElements["Actual alarm"].value as? String)?.contains("6:22") == true)
        wakeBy.tap()
        XCTAssertEqual(wakeBy.value as? String, "Off")
        XCTAssertTrue((alarm.value as? String)?.contains("6:22") == true)
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
        let dial = app.otherElements["sleepDial"]
        let frameWithoutWarning = dial.frame

        let bedtimeLock = app.buttons["Fix Bedtime"]
        XCTAssertTrue(bedtimeLock.isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        bedtimeLock.tap()
        XCTAssertEqual(bedtimeLock.value as? String, "Locked")
        let alarmLock = app.buttons["Fix Alarm"]
        alarmLock.tap()
        XCTAssertEqual(alarmLock.value as? String, "Locked")
        XCTAssertTrue(app.staticTexts["Incomplete REM"]
            .waitForExistence(timeout: 3))
        XCTAssertEqual(dial.frame.width, frameWithoutWarning.width, accuracy: 0.5)
        XCTAssertEqual(dial.frame.height, frameWithoutWarning.height, accuracy: 0.5)
        XCTAssertEqual(dial.frame.midX, frameWithoutWarning.midX, accuracy: 0.5)
        XCTAssertEqual(dial.frame.midY, frameWithoutWarning.midY, accuracy: 0.5)
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
        app.buttons["Fix Bedtime"].tap()
        app.buttons["Fix Alarm"].tap()
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
        XCTAssertEqual(app.buttons["Fix Bedtime"].value as? String, "Locked")
        XCTAssertEqual(app.buttons["Fix Alarm"].value as? String, "Locked")
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
