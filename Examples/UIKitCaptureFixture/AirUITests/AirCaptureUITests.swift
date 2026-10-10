import XCTest

/// Opt-in physical-device research. Positive screen-recording permission is
/// granted manually by the user. Reconnaissance supplies cancellation selectors.
@MainActor
final class AirCaptureUITests: XCTestCase {
    private let fixture = XCUIApplication(bundleIdentifier: "dev.screener.UIKitFixture")
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    func testScreenCaptureResearch() throws {
        try XCTSkipUnless(environment["SCREENER_AIR_RESEARCH"] == "1", "Explicit Air research opt-in required")
        #if targetEnvironment(simulator)
        throw XCTSkip("This experiment requires physical iPhone Air")
        #else
        continueAfterFailure = false
        let phase = environment["SCREENER_AIR_PHASE"] ?? "reconnaissance"
        XCTAssertTrue(["reconnaissance", "capture", "cancel"].contains(phase))
        fixture.launchArguments = [environment["SCREENER_AIR_SDK_TRACE"] == "1"
            ? "--screencapturekit-trace" : "--screencapturekit-probe"]
        fixture.launch()
        XCTAssertTrue(fixture.wait(for: .runningForeground, timeout: 20))
        // A bounded settling interval lets the system-owned picker become visible.
        settle(seconds: 3)
        attachEvidence("01-before-picker-action")
        guard phase != "reconnaissance" else { return }

        let status = fixture.staticTexts["fixture.captureStatus"]
        let alreadyRunning = status.exists && status.label == "running"
        if phase == "capture" {
            let note = XCTAttachment(string: "Positive recording permission is human-assisted. This test never taps an approval button; it waits up to 60 seconds for user-approved capture to report running. An already-running state does not establish automated consent.")
            note.name = "human-assisted-recording-permission"
            note.lifetime = .keepAlways
            add(note)
            expectStatus("running", timeout: 60)
            attachEvidence("02-after-human-approved-start")
        } else {
            try XCTSkipIf(alreadyRunning, "No picker visible: cancellation cannot be verified after capture already started")
            let labelKey = "SCREENER_AIR_CANCEL_LABEL"
            let exactLabel = try XCTUnwrap(environment[labelKey], "Set \(labelKey) from reconnaissance hierarchy")
            XCTAssertFalse(exactLabel.isEmpty)
            let owner = XCUIApplication(bundleIdentifier: environment["SCREENER_AIR_PICKER_BUNDLE"] ?? "com.apple.springboard")
            let button = owner.buttons.matching(NSPredicate(format: "label == %@", exactLabel))
            XCTAssertTrue(button.firstMatch.waitForExistence(timeout: 15))
            XCTAssertEqual(button.count, 1, "Cancellation must resolve to exactly one observed button")
            XCTAssertTrue(button.element.isHittable)
            button.element.tap()
            attachEvidence("02-after-cancellation-action")
        }

        if phase == "cancel" {
            expectStatus("finished")
            attachEvidence("03-cancelled")
            return
        }

        expectStatus("running")
        settle(seconds: 3)
        attachEvidence("03-base-materials")
        let save = fixture.buttons["fixture.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(fixture.buttons["Files"].waitForExistence(timeout: 10))
        XCTAssertTrue(fixture.buttons["Photos"].exists)
        XCTAssertTrue(fixture.buttons["Share"].exists)
        settle(seconds: 3)
        attachEvidence("04-save-menu")
        // The fixture's Files action is intentionally empty and dismisses its menu.
        fixture.buttons["Files"].tap()
        let stop = fixture.buttons["fixture.stopCapture"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        XCTAssertTrue(stop.isHittable)
        stop.tap()
        expectStatus("finished")
        attachEvidence("05-stopped")
        #endif
    }

    private func expectStatus(_ value: String, timeout: TimeInterval = 20) {
        let status = fixture.staticTexts["fixture.captureStatus"]
        let predicate = NSPredicate(format: "label == %@", value)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed, "Expected capture status \(value)")
    }

    private func attachEvidence(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: "FIXTURE\n\(fixture.debugDescription)\nSPRINGBOARD\n\(springboard.debugDescription)")
        hierarchy.name = "\(name)-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func settle(seconds: TimeInterval) {
        let settled = expectation(description: "Allow capture publication and UI to settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { settled.fulfill() }
        wait(for: [settled], timeout: seconds + 2)
    }
}
