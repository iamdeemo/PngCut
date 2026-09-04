import XCTest
@testable import PngCut

final class FailureCatalogTests: XCTestCase {
    func testFailureCatalogMatchesTheSharedContract() throws {
        for entry in try SharedContractLoader.errorCatalog().errors {
            guard let code = FailureCode(rawValue: entry.code) else {
                return XCTFail("Missing local failure code \(entry.code).")
            }
            XCTAssertEqual(FailureCatalog.message(for: code), entry.message)
        }
    }

    func testEngineFailurePresentationDoesNotExposeTechnicalDetails() {
        let failure = CompressionFailure(
            code: .engineFailed,
            technicalMessage: "/private/input.png: process --unsafe-command failed"
        )
        let message = FailureCatalog.message(for: failure.code)

        XCTAssertEqual(message, "压缩程序执行失败。")
        XCTAssertFalse(message.contains("/private/input.png"))
        XCTAssertFalse(message.contains("--unsafe-command"))
    }
}
