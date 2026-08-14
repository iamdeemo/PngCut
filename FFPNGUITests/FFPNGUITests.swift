import XCTest

final class FFPNGUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testEmptyStateShowsSelectionControlsAndDisabledFolder() {
        XCTAssertTrue(app.buttons["chooseFilesButton"].exists)
        XCTAssertFalse(app.buttons["revealOutputButton"].isEnabled)
    }

    func testContentDoesNotAddASecondTitleBarSpacer() {
        XCTAssertFalse(app.otherElements["titleBarBackground"].exists)
    }

    func testSettingsDrawerOpensAndCloses() {
        let settings = app.buttons["settingsButton"]
        settings.tap()
        let settingsDrawer = app.staticTexts["保存位置"]
        XCTAssertTrue(settingsDrawer.waitForExistence(timeout: 2))
        settings.tap()
        XCTAssertFalse(settingsDrawer.waitForExistence(timeout: 1))
    }

    func testSettingsDrawerClosesWhenBlankWorkspaceIsClicked() {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.buttons["settingsDismissArea"].waitForExistence(timeout: 2))

        app.windows.firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .tap()

        XCTAssertFalse(app.staticTexts["保存位置"].waitForExistence(timeout: 2))
    }

    func testBottomBarOffersDisabledBalancedShortcutBeforeValidation() {
        XCTAssertTrue(app.buttons["modeShortcutLossless"].waitForExistence(timeout: 2))
        let balanced = app.buttons["modeShortcutBalanced"]
        XCTAssertTrue(balanced.exists)
        XCTAssertFalse(balanced.isEnabled)
    }

    func testBalancedModeIsDisabledBeforeValidation() {
        app.buttons["settingsButton"].tap()
        let balanced = app.buttons["balancedMode"]
        XCTAssertTrue(balanced.waitForExistence(timeout: 2))
        XCTAssertFalse(balanced.isEnabled)
    }

    func testSettingsShowsTinifyKeyAsVisibleTextBeforeBalancedModeIsValidated() {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.textFields["tinifyAPIKeyField"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.secureTextFields["tinifyAPIKeyField"].exists)
    }

    func testValidatedKeyKeepsTinifyConfigurationVisible() {
        app.terminate()
        app.launchArguments = [
            "-tinify-api-key", "validated-test-key",
            "-validated-tinify-api-key", "validated-test-key",
            "-ffpng.compression-mode", "balanced"
        ]
        app.launch()

        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.textFields["tinifyAPIKeyField"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["已验证"].exists)
        XCTAssertTrue(app.buttons["重新验证"].exists)
    }
}
