import XCTest

final class PngCutUITests: XCTestCase {
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

    func testBottomBarOffersEnabledBalancedShortcut() {
        XCTAssertTrue(app.buttons["modeShortcutLossless"].waitForExistence(timeout: 2))
        let balanced = app.buttons["modeShortcutBalanced"]
        XCTAssertTrue(balanced.exists)
        XCTAssertTrue(balanced.isEnabled)
    }

    func testBottomBarControlsRemainSeparatelyAccessible() {
        let lossless = app.buttons["modeShortcutLossless"]
        let balanced = app.buttons["modeShortcutBalanced"]
        let output = app.buttons["revealOutputButton"]
        let settings = app.buttons["settingsButton"]

        XCTAssertTrue(lossless.waitForExistence(timeout: 2))
        XCTAssertTrue(lossless.isHittable)
        XCTAssertTrue(balanced.isHittable)
        XCTAssertTrue(output.exists)
        XCTAssertTrue(settings.isHittable)
    }

    func testBalancedModeIsAvailableInSettings() {
        app.buttons["settingsButton"].tap()
        let balanced = app.buttons["balancedMode"]
        XCTAssertTrue(balanced.waitForExistence(timeout: 2))
        XCTAssertTrue(balanced.isEnabled)
        XCTAssertTrue(app.staticTexts["本地有损压缩"].exists)
    }

    func testSettingsDoesNotShowTinifyConfiguration() {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.staticTexts["保存位置"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.textFields.matching(identifier: "tinifyAPIKeyField").count, 0)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Tinify")).count, 0)
    }

    func testSettingsDrawerOffersGIFControls() {
        app.buttons["settingsButton"].tap()

        XCTAssertTrue(app.checkBoxes["pngSequenceGIFEnabled"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["gifFrameRate20"].exists)
        XCTAssertTrue(app.buttons["gifFrameRate25"].exists)
        XCTAssertTrue(app.buttons["gifFrameRate30"].exists)
        XCTAssertTrue(app.buttons["gifFrameRateCustom"].exists)
        XCTAssertTrue(app.textFields["gifCustomFrameRate"].exists)
        XCTAssertTrue(app.buttons["gifLoopForever"].exists)
        XCTAssertTrue(app.buttons["gifLoopOnce"].exists)
    }

    func testNoSequenceDecisionBlocksImportUntilNoticeIsAcknowledged() {
        app.terminate()
        app.launchArguments = ["--ui-test-no-sequence-decision"]
        app.launch()

        let title = app.staticTexts["未发现 PNG 序列"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["chooseFilesButton"].isEnabled)
        XCTAssertTrue(app.buttons["不压缩"].isHittable)

        app.buttons["不压缩"].tap()
        XCTAssertTrue(app.staticTexts["当前文件夹没有 PNG 序列，无法转 GIF"].waitForExistence(timeout: 2))
        app.buttons["好"].tap()

        XCTAssertFalse(title.exists)
        XCTAssertTrue(app.buttons["chooseFilesButton"].isEnabled)
    }

    func testSequenceDecisionShowsBothExplicitActions() {
        app.terminate()
        app.launchArguments = ["--ui-test-sequence-decision"]
        app.launch()

        XCTAssertTrue(app.staticTexts["发现 PNG 序列"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["转 GIF"].isHittable)
        XCTAssertTrue(app.buttons["常规压缩"].isHittable)
        XCTAssertFalse(app.buttons["chooseFilesButton"].isEnabled)
    }
}
