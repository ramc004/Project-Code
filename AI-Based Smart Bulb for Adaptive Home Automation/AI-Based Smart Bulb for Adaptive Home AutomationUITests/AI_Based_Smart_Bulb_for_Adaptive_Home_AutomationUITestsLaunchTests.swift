//
//  AI_Based_Smart_Bulb_for_Adaptive_Home_AutomationUITestsLaunchTests.swift
//  AI-Based Smart Bulb for Adaptive Home AutomationUITests
//
//  Created by Caleb Ram on 18/11/2025.
//

import XCTest

final class AI_Based_Smart_Bulb_for_Adaptive_Home_AutomationUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
