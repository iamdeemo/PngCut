import XCTest
@testable import PngCut

final class GIFSettingsTests: XCTestCase {
    func testDefaultsDisablePNGSequenceConversionWithThirtyFPSAndForeverLooping() {
        let settings = GIFSettings()

        XCTAssertFalse(settings.isPNGSequenceConversionEnabled)
        XCTAssertEqual(settings.frameRate, .preset(30))
        XCTAssertEqual(settings.loop, .forever)
    }

    func testCustomFrameRateAcceptsBothInclusiveBoundaryValues() {
        XCTAssertEqual(GIFFrameRate.custom(validating: 1), .custom(1))
        XCTAssertEqual(GIFFrameRate.custom(validating: 50), .custom(50))
    }

    func testCustomFrameRateRejectsValuesOutsideTheSupportedRange() {
        XCTAssertNil(GIFFrameRate.custom(validating: 0))
        XCTAssertNil(GIFFrameRate.custom(validating: 51))
    }

    func testFrameRateExposesPresetAndCustomValues() {
        XCTAssertEqual(GIFFrameRate.presetValues, [20, 25, 30])
        XCTAssertEqual(GIFFrameRate.preset(25).value, 25)
        XCTAssertEqual(GIFFrameRate.custom(17).value, 17)
    }

    func testGIFLoopUsesTheExpectedGifskiRepeatArguments() {
        XCTAssertEqual(GIFLoop.forever.gifskiRepeatArgument, 0)
        XCTAssertEqual(GIFLoop.once.gifskiRepeatArgument, -1)
    }
}
