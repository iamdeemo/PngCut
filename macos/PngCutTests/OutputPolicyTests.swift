import XCTest
@testable import PngCut

final class OutputPolicyTests: XCTestCase {
    private var directory: URL!
    private var source: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-OutputPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("banner.png")
        try Data("source".utf8).write(to: source)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testAdjacentOutputAddsPngcutSuffix() throws {
        let prepared = try OutputPolicy.adjacent.prepare(source: source)

        XCTAssertEqual(prepared.finalURL, directory.appendingPathComponent("banner_pngcut.png"))
    }

    func testAdjacentJPEGOutputPreservesNormalizedExtensionForFinalAndTemporaryFiles() throws {
        let jpegSource = directory.appendingPathComponent("photo.JPEG")
        try Data("source".utf8).write(to: jpegSource)

        let prepared = try OutputPolicy.adjacent.prepare(source: jpegSource)

        XCTAssertEqual(prepared.finalURL, directory.appendingPathComponent("photo_pngcut.jpeg"))
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

        XCTAssertEqual(prepared.finalURL, customDirectory.appendingPathComponent("banner_pngcut.png"))
    }

    func testCustomOutputAvoidsAnExistingPngcutFile() throws {
        let customDirectory = directory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: customDirectory, withIntermediateDirectories: true)
        let existingOutput = customDirectory.appendingPathComponent("banner_pngcut.png")
        try Data("existing output".utf8).write(to: existingOutput)

        let prepared = try OutputPolicy.customDirectory.prepare(source: source, customDirectory: customDirectory)

        XCTAssertEqual(prepared.finalURL, customDirectory.appendingPathComponent("banner_pngcut-2.png"))
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

        XCTAssertEqual(first.finalURL, customDirectory.appendingPathComponent("icon_pngcut.png"))
        XCTAssertEqual(second.finalURL, customDirectory.appendingPathComponent("icon_pngcut-2.png"))
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

        XCTAssertEqual(second.finalURL, customDirectory.appendingPathComponent("ICON_pngcut-2.png"))
        XCTAssertEqual(try Data(contentsOf: firstSource), Data("first source".utf8))
        XCTAssertEqual(try Data(contentsOf: secondSource), Data("second source".utf8))
    }

    func testOverwriteKeepsSourceAsFinalAndUsesDifferentTemporarySibling() throws {
        let prepared = try OutputPolicy.overwrite.prepare(source: source)

        XCTAssertEqual(prepared.finalURL, source)
        XCTAssertNotEqual(prepared.temporaryURL, source)
        XCTAssertEqual(prepared.temporaryURL.deletingLastPathComponent(), directory)
    }

    func testGeneratedGIFWithOverwriteUsesAdjacentNonReplacingOutput() throws {
        var planner = OutputPlanner(policy: .overwrite, customDirectory: nil, reservedFinalURLs: [])

        let prepared = try planner.prepareGeneratedGIF(
            representativeSource: source,
            outputFileName: "walk.gif"
        )

        XCTAssertEqual(prepared.finalURL, directory.appendingPathComponent("walk.gif"))
        XCTAssertFalse(prepared.allowsReplacingExistingFile)
        XCTAssertEqual(prepared.temporaryURL.deletingLastPathComponent(), directory)
    }

    func testGeneratedGIFAvoidsExistingOutputName() throws {
        let existingOutput = directory.appendingPathComponent("walk.gif")
        try Data("existing output".utf8).write(to: existingOutput)
        var planner = OutputPlanner(policy: .adjacent, customDirectory: nil, reservedFinalURLs: [])

        let prepared = try planner.prepareGeneratedGIF(
            representativeSource: source,
            outputFileName: "walk.gif"
        )

        XCTAssertEqual(prepared.finalURL, directory.appendingPathComponent("walk-2.gif"))
        XCTAssertEqual(try Data(contentsOf: existingOutput), Data("existing output".utf8))
    }

    func testGeneratedGIFReservesDistinctNamesInOneBatch() throws {
        var planner = OutputPlanner(policy: .adjacent, customDirectory: nil, reservedFinalURLs: [])

        let first = try planner.prepareGeneratedGIF(
            representativeSource: source,
            outputFileName: "walk.gif"
        )
        let second = try planner.prepareGeneratedGIF(
            representativeSource: source,
            outputFileName: "walk.gif"
        )

        XCTAssertEqual(first.finalURL, directory.appendingPathComponent("walk.gif"))
        XCTAssertEqual(second.finalURL, directory.appendingPathComponent("walk-2.gif"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.finalURL.path))
    }

    func testGeneratedGIFFolderImportPreservesRepresentativeRelativeDirectory() throws {
        let selectedRoot = directory.appendingPathComponent("root", isDirectory: true)
        let nestedDirectory = selectedRoot.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let representativeSource = nestedDirectory.appendingPathComponent("frame-001.png")
        try Data("frame".utf8).write(to: representativeSource)
        var planner = OutputPlanner(policy: .adjacent, customDirectory: nil, reservedFinalURLs: [])

        let prepared = try planner.prepareGeneratedGIF(
            representativeSource: representativeSource,
            outputFileName: "walk.gif",
            importedFolderRoot: selectedRoot
        )

        XCTAssertEqual(
            prepared.finalURL,
            directory.appendingPathComponent("root_pngcut/nested/walk.gif")
        )
        XCTAssertFalse(prepared.allowsReplacingExistingFile)
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
