import XCTest

final class PngCutUITests: XCTestCase {
    private static let isolatedPreferencesArgument = "--ui-test-isolated-preferences"
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [Self.isolatedPreferencesArgument]
        app.launch()
    }

    func testReferenceWindowChromeAndEmptyStateArePresent() {
        XCTAssertTrue(app.staticTexts["windowTitle"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["windowTitle"].value as? String, "PngCut")
        XCTAssertLessThan(app.staticTexts["windowTitle"].frame.maxY - app.windows.firstMatch.frame.minY, 42)
        XCTAssertTrue(app.otherElements["figmaDropZone"].exists)
        XCTAssertTrue(app.buttons["chooseFilesButton"].isHittable)
        XCTAssertFalse(app.buttons["revealOutputButton"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "PngCut-Minimal-Home-Default"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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
        XCTAssertFalse(app.staticTexts["本地有损压缩"].exists)
        let gap = balanced.frame.minX - app.buttons["losslessMode"].frame.maxX
        XCTAssertGreaterThanOrEqual(gap, 16)
        XCTAssertLessThanOrEqual(gap, 32)
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
        app.launchArguments = [Self.isolatedPreferencesArgument, "--ui-test-wide-window"]
        app.launch()

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 2))
        XCTAssertGreaterThan(app.windows.firstMatch.frame.width, 1_000)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "PngCut-Minimal-Home-Wide"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["settingsButton"].tap()
        let output = app.staticTexts["保存位置"]
        let compression = app.staticTexts["压缩方式"]
        let gif = app.staticTexts["GIF 设置"]
        XCTAssertTrue(gif.waitForExistence(timeout: 2))

        XCTAssertGreaterThan(compression.frame.minY, output.frame.maxY)
        XCTAssertGreaterThan(gif.frame.minY, compression.frame.maxY)
        XCTAssertLessThan(abs(compression.frame.minX - output.frame.minX), 8)
        XCTAssertLessThan(abs(gif.frame.minX - output.frame.minX), 8)
        XCTAssertLessThanOrEqual(app.buttons["balancedMode"].frame.minX - app.buttons["losslessMode"].frame.maxX, 32)
    }

    func testCustomOutputPathSavesAndAllSettingsFitWithoutScrolling() {
        app.buttons["settingsButton"].tap()
        app.buttons["customOutputDirectoryOption"].tap()
        let path = app.textFields["outputDirectoryPath"]
        XCTAssertTrue(path.waitForExistence(timeout: 2))
        XCTAssertTrue(path.isHittable)
        path.click()
        path.typeText("/tmp\n")

        app.buttons["settingsButton"].tap()
        app.buttons["settingsButton"].tap()
        XCTAssertEqual(app.textFields["outputDirectoryPath"].value as? String, "/tmp")
        app.checkBoxes["pngSequenceGIFEnabled"].tap()
        XCTAssertTrue(app.buttons["gifLoopOnce"].isEnabled)
        let footerTop = app.buttons["settingsButton"].frame.minY
        for control in [app.buttons["gifLoopForever"], app.buttons["gifLoopOnce"], app.textFields["gifCustomFrameRate"]] {
            XCTAssertTrue(control.isHittable)
            XCTAssertLessThan(control.frame.maxY, footerTop)
        }
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "PngCut-Compact-C-Settings"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testInvalidOutputPathShowsInlineErrorAndDoesNotReplaceSavedPath() {
        app.buttons["settingsButton"].tap()
        app.buttons["customOutputDirectoryOption"].tap()
        let path = app.textFields["outputDirectoryPath"]
        path.click()
        path.typeText("/tmp\n")
        path.typeKey("a", modifierFlags: .command)
        path.typeText("/tmp/pngcut-missing-\(UUID().uuidString)\n")
        XCTAssertTrue((app.staticTexts["outputDirectoryPathMessage"].value as? String ?? "").contains("文件夹不存在"))
        app.buttons["settingsButton"].tap()
        app.buttons["settingsButton"].tap()
        XCTAssertEqual(app.textFields["outputDirectoryPath"].value as? String, "/tmp")
    }

    func testIsolatedLaunchStartsWithPNGSequenceConversionDisabled() {
        app.terminate()
        app.launchArguments = [Self.isolatedPreferencesArgument]
        app.launch()

        app.buttons["settingsButton"].tap()
        let pngSequenceGIFEnabled = app.checkBoxes["pngSequenceGIFEnabled"]
        XCTAssertTrue(pngSequenceGIFEnabled.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["gifFrameRate30"].isEnabled)
        XCTAssertFalse(app.buttons["gifLoopForever"].isEnabled)
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

    func testTaskFixtureShowsProcessingCompletedAndRetryableFailureStates() {
        app.terminate()
        app.launchArguments = [Self.isolatedPreferencesArgument, "--ui-test-task-states"]
        app.launch()

        XCTAssertTrue(app.staticTexts["任务列表"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["taskStateProcessing"].exists)
        XCTAssertTrue(app.otherElements["taskStateCompleted"].exists)
        XCTAssertTrue(app.otherElements["taskStateFailed"].exists)
        XCTAssertTrue(app.buttons["retryFailedButton"].isHittable)
        XCTAssertTrue(app.buttons["addFilesButton"].isHittable)
    }

    func testNoSequenceDecisionBlocksImportUntilNoticeIsAcknowledged() {
        app.terminate()
        app.launchArguments = [Self.isolatedPreferencesArgument, "--ui-test-no-sequence-decision"]
        app.launch()

        let title = app.staticTexts["未发现 PNG 序列"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        app.activate()
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
        app.launchArguments = [Self.isolatedPreferencesArgument, "--ui-test-sequence-decision"]
        app.launch()

        XCTAssertTrue(app.staticTexts["发现 PNG 序列"].waitForExistence(timeout: 2))
        app.activate()
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "PngCut-Compact-C-Dialog"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.buttons["转 GIF"].isHittable)
        XCTAssertTrue(app.buttons["常规压缩"].isHittable)
        XCTAssertEqual(app.buttons["常规压缩"].frame.height, app.buttons["转 GIF"].frame.height, accuracy: 1)
        XCTAssertFalse(app.buttons["chooseFilesButton"].isEnabled)
        app.buttons["常规压缩"].tap()
        XCTAssertFalse(app.staticTexts["发现 PNG 序列"].exists)
    }
}
