import XCTest
@testable import FFPNG

final class FileDiscoveryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFPNG-FileDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDiscoverFindsRegularPNGFilesRecursivelyIgnoringExtensionCase() throws {
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let rootPNG = try makeFile("root.PNG", in: directory)
        let nestedPNG = try makeFile("image.pNg", in: nested)
        _ = try makeFile("readme.txt", in: directory)

        let result = FileDiscovery().discover(urls: [directory])

        XCTAssertEqual(Set(result.files), Set([rootPNG.standardizedFileURL, nestedPNG.standardizedFileURL]))
        XCTAssertEqual(result.skippedNonImageCount, 1)
    }

    func testDiscoverDeduplicatesStandardizedInputURLs() throws {
        let image = try makeFile("image.png", in: directory)
        let duplicate = directory.appendingPathComponent("nested/../image.png")

        let result = FileDiscovery().discover(urls: [image, duplicate])

        XCTAssertEqual(result.files, [image.standardizedFileURL])
        XCTAssertEqual(result.skippedNonImageCount, 0)
    }

    func testDiscoverCountsSelectedNonImageFilesAsSkipped() throws {
        let document = try makeFile("document.pdf", in: directory)

        let result = FileDiscovery().discover(urls: [document])

        XCTAssertTrue(result.files.isEmpty)
        XCTAssertEqual(result.skippedNonImageCount, 1)
    }

    func testDiscoverFindsPNGsAndJPEGsRecursivelyIgnoringExtensionCase() throws {
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let icon = try makeFile("icon.PNG", in: directory)
        let photo = try makeFile("photo.JpG", in: nested)
        let scan = try makeFile("scan.JPEG", in: nested)
        _ = try makeFile("notes.pdf", in: nested)

        let result = FileDiscovery().discover(urls: [directory])

        XCTAssertEqual(Set(result.files), Set([
            icon.standardizedFileURL,
            photo.standardizedFileURL,
            scan.standardizedFileURL
        ]))
        XCTAssertEqual(result.skippedNonImageCount, 1)
    }

    func testCompressionTaskDefaultsToLosslessDisplayMode() {
        let task = CompressionTask(sourceURL: directory.appendingPathComponent("image.png"))

        XCTAssertEqual(task.displayMode, .lossless)
    }

    private func makeFile(_ name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }
}
