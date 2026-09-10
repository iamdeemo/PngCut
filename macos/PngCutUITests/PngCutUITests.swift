import XCTest

final class PngCutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testReferenceWindowChromeAndEmptyStateArePresent() {
        XCTAssertTrue(app.staticTexts["windowTitle"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["figmaDropZone"].exists)
        XCTAssertTrue(app.buttons["chooseFilesButton"].isHittable)
        XCTAssertFalse(app.buttons["revealOutputButton"].isEnabled)
    }

    func testEmptyStateShowsOnlySupportedFormatTags() {
        XCTAssertTrue(app.staticTexts["formatPNG"].exists)
        XCTAssertTrue(app.staticTexts["formatJPG"].exists)
        XCTAssertTrue(app.staticTexts["formatGIF"].exists)
        XCTAssertEqual(app.staticTexts.matching(identifier: "formatWEBP").count, 0)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "WEBP")).count, 0)
    }

    func testSettingsSurfaceOpensAndClosesFromTheToolbar() {
        let settings = app.buttons["settingsButton"]
        settings.tap()
        XCTAssertTrue(app.otherElements["settingsSurface"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["保存位置"].exists)
        settings.tap()
        XCTAssertFalse(app.otherElements["settingsSurface"].waitForExistence(timeout: 2))
    }

    func testBottomBarOffersEnabledBalancedShortcut() {
        XCTAssertTrue(app.buttons["modeShortcutLossless"].waitForExistence(timeout: 2))
        let balanced = app.buttons["modeShortcutBalanced"]
        XCTAssertTrue(balanced.exists)
        XCTAssertTrue(balanced.isEnabled)
    }

    func testReferenceToolbarKeepsAllActionsSeparatelyAccessible() {
        XCTAssertTrue(app.buttons["modeShortcutLossless"].isHittable)
        XCTAssertTrue(app.buttons["modeShortcutBalanced"].isHittable)
        XCTAssertTrue(app.buttons["settingsButton"].isHittable)
        XCTAssertTrue(app.buttons["revealOutputButton"].exists)
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

    func testSettingsDrawerKeepsGIFLoopOptionsVisibleWithoutScrolling() {
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.staticTexts["GIF 设置"].waitForExistence(timeout: 2))

        let loopForever = app.buttons["gifLoopForever"]
        let loopOnce = app.buttons["gifLoopOnce"]
        XCTAssertTrue(loopForever.waitForExistence(timeout: 2))
        XCTAssertTrue(loopOnce.waitForExistence(timeout: 2))
        XCTAssertTrue(loopForever.isHittable)
        XCTAssertTrue(loopOnce.isHittable)
    }

    func testWideSettingsKeepsReferenceVerticalGroupOrder() {
        app.terminate()
        app.launchArguments = ["--ui-test-wide-window"]
        app.launch()

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 2))
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, 1_000)

        app.buttons["settingsButton"].tap()
        let output = app.staticTexts["保存位置"]
        let compression = app.staticTexts["压缩方式"]
        let gif = app.staticTexts["GIF 设置"]
        XCTAssertTrue(gif.waitForExistence(timeout: 2))

        XCTAssertGreaterThan(compression.frame.minY, output.frame.maxY)
        XCTAssertGreaterThan(gif.frame.minY, compression.frame.maxY)
        XCTAssertLessThan(abs(compression.frame.minX - output.frame.minX), 8)
        XCTAssertLessThan(abs(gif.frame.minX - output.frame.minX), 8)
    }

    func testGIFControlsRemainVisibleButDisabledUntilPNGSequenceConversionIsEnabled() {
        app.buttons["settingsButton"].tap()
        let pngSequenceGIFEnabled = app.checkBoxes["pngSequenceGIFEnabled"]
        XCTAssertTrue(pngSequenceGIFEnabled.waitForExistence(timeout: 2))
        if app.buttons["gifFrameRate30"].isEnabled {
            pngSequenceGIFEnabled.tap()
        }
        XCTAssertFalse(app.buttons["gifFrameRate30"].isEnabled)
        XCTAssertFalse(app.buttons["gifLoopForever"].isEnabled)
        pngSequenceGIFEnabled.tap()
        XCTAssertTrue(app.buttons["gifFrameRate30"].isEnabled)
        XCTAssertTrue(app.buttons["gifLoopForever"].isEnabled)
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
