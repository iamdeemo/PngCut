import XCTest
@testable import FFPNG

final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = KeychainStore(
            service: "com.ffpng.tests.\(UUID().uuidString)",
            account: "tinify-api-key"
        )
    }

    override func tearDownWithError() throws {
        try store.delete()
        store = nil
        try super.tearDownWithError()
    }

    func testSaveLoadAndDeleteAPIKey() throws {
        XCTAssertNil(try store.load())

        try store.save("test-api-key")
        XCTAssertEqual(try store.load(), "test-api-key")

        try store.delete()
        XCTAssertNil(try store.load())
    }

    func testSaveReplacesExistingAPIKey() throws {
        try store.save("old-key")
        try store.save("new-key")

        XCTAssertEqual(try store.load(), "new-key")
    }
}
