import XCTest
@testable import FFPNG

final class OutputPolicyTests: XCTestCase {
    private var directory: URL!
    private var source: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFPNG-OutputPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("banner.png")
        try Data("source".utf8).write(to: source)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAdjacentOutputAddsOptimizedSuffix() throws {
        let prepared = try OutputPolicy.adjacent.prepare(source: source)

        XCTAssertEqual(prepared.finalURL, directory.appendingPathComponent("banner-optimized.png"))
    }

    func testAdjacentJPEGOutputPreservesNormalizedExtensionForFinalAndTemporaryFiles() throws {
        let jpegSource = directory.appendingPathComponent("photo.JPEG")
        try Data("source".utf8).write(to: jpegSource)

        let prepared = try OutputPolicy.adjacent.prepare(source: jpegSource)

        XCTAssertEqual(prepared.finalURL, directory.appendingPathComponent("photo-optimized.jpeg"))
        XCTAssertEqual(prepared.temporaryURL.pathExtension, "jpeg")
    }

    func testCustomOutputRequiresExistingDirectory() throws {
        let missingDirectory = directory.appendingPathComponent("missing", isDirectory: true)

        XCTAssertThrowsError(try OutputPolicy.customDirectory.prepare(source: source, customDirectory: nil)) { error in
            XCTAssertEqual(error as? OutputPolicyError, .customDirectoryRequired)
        }
        XCTAssertThrowsError(try OutputPolicy.customDirectory.prepare(source: source, customDirectory: missingDirectory)) { error in
            XCTAssertEqual(error as? OutputPolicyError, .customDirectoryDoesNotExist(missingDirectory.standardizedFileURL))
        }
    }

    func testCustomOutputUsesAnExistingDirectory() throws {
        let customDirectory = directory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)

        let prepared = try OutputPolicy.customDirectory.prepare(source: source, customDirectory: customDirectory)

        XCTAssertEqual(prepared.finalURL, customDirectory.appendingPathComponent("banner-optimized.png"))
    }

    func testCustomOutputAvoidsAnExistingOptimizedFile() throws {
        let customDirectory = directory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
        let existingOutput = customDirectory.appendingPathComponent("banner-optimized.png")
        try Data("existing output".utf8).write(to: existingOutput)

        let prepared = try OutputPolicy.customDirectory.prepare(source: source, customDirectory: customDirectory)

        XCTAssertEqual(prepared.finalURL, customDirectory.appendingPathComponent("banner-optimized-2.png"))
        XCTAssertEqual(try Data(contentsOf: existingOutput), Data("existing output".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))
    }

    func testCustomOutputReservesDistinctDestinationsForSameNameSourcesInOneBatch() throws {
        let customDirectory = directory.appendingPathComponent("output", isDirectory: true)
        let firstSourceDirectory = directory.appendingPathComponent("a", isDirectory: true)
        let secondSourceDirectory = directory.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstSourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSourceDirectory, withIntermediateDirectories: true)
        let firstSource = firstSourceDirectory.appendingPathComponent("icon.png")
        let secondSource = secondSourceDirectory.appendingPathComponent("icon.png")
        try Data("first source".utf8).write(to: firstSource)
        try Data("second source".utf8).write(to: secondSource)

        let first = try OutputPolicy.customDirectory.prepare(source: firstSource, customDirectory: customDirectory)
        let second = try OutputPolicy.customDirectory.prepare(
            source: secondSource,
            customDirectory: customDirectory,
            reservedFinalURLs: [first.finalURL]
        )

        XCTAssertEqual(first.finalURL, customDirectory.appendingPathComponent("icon-optimized.png"))
        XCTAssertEqual(second.finalURL, customDirectory.appendingPathComponent("icon-optimized-2.png"))
        XCTAssertEqual(try Data(contentsOf: firstSource), Data("first source".utf8))
        XCTAssertEqual(try Data(contentsOf: secondSource), Data("second source".utf8))
    }

    func testCustomOutputReservesDistinctDestinationsForSourceNamesThatDifferOnlyByCase() throws {
        let customDirectory = directory.appendingPathComponent("output", isDirectory: true)
        let firstSourceDirectory = directory.appendingPathComponent("a", isDirectory: true)
        let secondSourceDirectory = directory.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: firstSourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSourceDirectory, withIntermediateDirectories: true)
        let firstSource = firstSourceDirectory.appendingPathComponent("icon.png")
        let secondSource = secondSourceDirectory.appendingPathComponent("ICON.png")
        try Data("first source".utf8).write(to: firstSource)
        try Data("second source".utf8).write(to: secondSource)

        let first = try OutputPolicy.customDirectory.prepare(source: firstSource, customDirectory: customDirectory)
        let second = try OutputPolicy.customDirectory.prepare(
            source: secondSource,
            customDirectory: customDirectory,
            reservedFinalURLs: [first.finalURL]
        )

        XCTAssertEqual(second.finalURL, customDirectory.appendingPathComponent("ICON-optimized-2.png"))
        XCTAssertEqual(try Data(contentsOf: firstSource), Data("first source".utf8))
        XCTAssertEqual(try Data(contentsOf: secondSource), Data("second source".utf8))
    }

    func testOverwriteKeepsSourceAsFinalAndUsesDifferentTemporarySibling() throws {
        let prepared = try OutputPolicy.overwrite.prepare(source: source)

        XCTAssertEqual(prepared.finalURL, source)
        XCTAssertNotEqual(prepared.temporaryURL, source)
        XCTAssertEqual(prepared.temporaryURL.deletingLastPathComponent(), directory)
    }

    func testEachPreparedOutputGetsUniqueTemporarySibling() throws {
        let first = try OutputPolicy.adjacent.prepare(source: source)
        let second = try OutputPolicy.adjacent.prepare(source: source)

        XCTAssertNotEqual(first.temporaryURL, second.temporaryURL)
        XCTAssertEqual(first.temporaryURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(second.temporaryURL.deletingLastPathComponent(), directory)
    }

    func testCommitMovesCompletedTemporaryOutputToFinalDestination() throws {
        let prepared = try OutputPolicy.adjacent.prepare(source: source)
        try Data("compressed".utf8).write(to: prepared.temporaryURL)

        try prepared.commit()

        XCTAssertEqual(try Data(contentsOf: prepared.finalURL), Data("compressed".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: prepared.temporaryURL.path))
    }

    func testTemporaryOutputDoesNotReplaceOriginalUntilCommit() throws {
        let prepared = try OutputPolicy.overwrite.prepare(source: source)
        try Data("compressed".utf8).write(to: prepared.temporaryURL)

        XCTAssertEqual(try Data(contentsOf: source), Data("source".utf8))

        try prepared.commit()

        XCTAssertEqual(try Data(contentsOf: source), Data("compressed".utf8))
    }
}
