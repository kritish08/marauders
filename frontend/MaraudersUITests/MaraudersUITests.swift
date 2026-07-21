import XCTest

final class MaraudersUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGoogleDemoLoginOpensTours() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["googleSignInButton"].tap()
        let toursTab = app.tabBars.buttons["My Tours"]
        XCTAssertTrue(toursTab.waitForExistence(timeout: 5))
        toursTab.tap()
        XCTAssertTrue(app.staticTexts["My Tours"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["viewTicket_taj-mahal"].exists)
        let zomato = app.buttons["viewTicket_zomato-farmhouse"]
        XCTAssertTrue(zomato.waitForExistence(timeout: 3))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: zomato)
        waitForExpectations(timeout: 15)
    }

    func testBundledTourReachesMap() {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Location permission") { alert in
            let allow = alert.buttons["Allow While Using App"]
            if allow.exists { allow.tap(); return true }
            return false
        }
        app.launch()
        app.buttons["googleSignInButton"].tap()
        let toursTab = app.tabBars.buttons["My Tours"]
        XCTAssertTrue(toursTab.waitForExistence(timeout: 5))
        toursTab.tap()
        let prepare = app.buttons["viewTicket_taj-mahal"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
        prepare.tap()
        let ready = app.staticTexts["Tour ready offline"]
        if !ready.waitForExistence(timeout: 2), prepare.exists {
            prepare.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(ready.waitForExistence(timeout: 10))
        app.buttons["startTourButton"].tap()
        app.tap()
        for id in ["start", "terrace", "mughal-charbagh", "mosque", "great-gate", "exit"] {
            XCTAssertTrue(app.buttons["tajRouteCheckpoint_\(id)"].waitForExistence(timeout: 5))
        }
        app.buttons["tajRouteCheckpoint_start"].tap()
        XCTAssertTrue(app.buttons["tajCompleteChapterButton"].waitForExistence(timeout: 5))
        app.buttons["tajCompleteChapterButton"].tap()
        XCTAssertTrue(app.buttons["tajBrowseStoriesButton"].exists)
        app.buttons["tajBrowseStoriesButton"].tap()
        if !app.navigationBars["Audio Experience"].waitForExistence(timeout: 2) { app.buttons["tajBrowseStoriesButton"].tap() }
        XCTAssertTrue(app.navigationBars["Audio Experience"].waitForExistence(timeout: 5))
        app.buttons["browseNugget_n_gate_illusion"].tap()
        XCTAssertTrue(app.staticTexts["nuggetRevealTitle_n_gate_illusion"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["nuggetGallery_n_gate_illusion"].exists)
        app.buttons["closeNuggetReveal"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["tajChapterProgress"].waitForExistence(timeout: 5))
    }
}
