import XCTest
@testable import PngCut

final class SharedContractDocumentTests: XCTestCase {
    func testSharedContractDocumentsExist() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for name in ["behavior.json", "discovery-cases.json", "output-policy-cases.json", "error-catalog.json", "engine-manifest.json"] {
            XCTAssertTrue(
                FileManager.default.fileExists(
                    atPath: root.appendingPathComponent("shared/contracts/v1/\(name)").path
                ),
                "Expected shared contract document \(name) to exist."
            )
        }
    }

    func testBehaviorContractVersionIsOne() throws {
        XCTAssertEqual(try SharedContractLoader.document(named: "behavior.json").version, 1)
    }
}
