import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import PngCut

final class PNGSequenceDetectorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-PNGSequenceDetectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDetectOrdersTenUnsortedPNGFramesNumericallyAndDerivesGIFName() throws {
        let numbers = [8, 1, 10, 4, 7, 3, 9, 2, 6, 5]
        let images = try numbers.map { number in
            try discoveredFile(named: "walk_\(String(format: "%04d", number)).png")
        }

        let sequences = PNGSequenceDetector().detect(in: images)

        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences[0].frameURLs.map(\.lastPathComponent), (1...10).map { "walk_\(String(format: "%04d", $0)).png" })
        XCTAssertEqual(sequences[0].importedFolderRoot, directory.standardizedFileURL)
        XCTAssertEqual(sequences[0].outputFileName, "walk.gif")
    }

    func testDetectRejectsASequenceWithOnlyNineFrames() throws {
        let images = try (1...9).map { try discoveredFile(named: "walk_\($0).png") }

        XCTAssertTrue(PNGSequenceDetector().detect(in: images).isEmpty)
    }

    func testDetectRejectsFramesWithANumericGap() throws {
        let numbers = Array(1...9) + [11]
        let images = try numbers.map { try discoveredFile(named: "walk_\($0).png") }

        XCTAssertTrue(PNGSequenceDetector().detect(in: images).isEmpty)
    }

    func testDetectDoesNotMergeMatchingFrameNamesFromSeparateFolders() throws {
        let firstFolder = directory.appendingPathComponent("first", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let first = try (1...5).map { try discoveredFile(named: "walk_\($0).png", in: firstFolder) }
        let second = try (6...10).map { try discoveredFile(named: "walk_\($0).png", in: secondFolder) }

        XCTAssertTrue(PNGSequenceDetector().detect(in: first + second).isEmpty)
    }

    func testDetectAcceptsZeroFilledFramesWithAnArbitraryStartNumber() throws {
        let images = try (7...16).reversed().map { number in
            try discoveredFile(named: "idle-\(String(format: "%04d", number)).PNG")
        }

        let sequences = PNGSequenceDetector().detect(in: images)

        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences[0].frameURLs.map(\.lastPathComponent), (7...16).map { "idle-\(String(format: "%04d", $0)).PNG" })
        XCTAssertEqual(sequences[0].outputFileName, "idle.gif")
    }

    func testDetectUsesNonEmptyFallbackNameForNumericOnlyFrameNames() throws {
        let images = try (1...10).reversed().map { number in
            try discoveredFile(named: "\(String(format: "%04d", number)).png")
        }

        let sequences = PNGSequenceDetector().detect(in: images)

        XCTAssertEqual(sequences.count, 1)
        XCTAssertEqual(sequences[0].outputFileName, "sequence.gif")
    }

    func testValidateFrameDimensionsAcceptsEqualImageIOHeaderDimensions() throws {
        let first = try makePNG(named: "frame_0001.png", width: 12, height: 8)
        let second = try makePNG(named: "frame_0002.png", width: 12, height: 8)
        let sequence = PNGSequence(
            frameURLs: [first, second],
            importedFolderRoot: directory,
            outputFileName: "frame.gif"
        )

        XCTAssertNoThrow(try PNGSequenceDetector().validateFrameDimensions(sequence))
    }

    func testValidateFrameDimensionsReportsOutputValidationFailureForMismatchedFrames() throws {
        let first = try makePNG(named: "frame_0001.png", width: 12, height: 8)
        let second = try makePNG(named: "frame_0002.png", width: 10, height: 8)
        let sequence = PNGSequence(
            frameURLs: [first, second],
            importedFolderRoot: directory,
            outputFileName: "frame.gif"
        )

        XCTAssertThrowsError(try PNGSequenceDetector().validateFrameDimensions(sequence)) { error in
            XCTAssertEqual(error as? CompressionFailure, CompressionFailure(
                code: .outputInvalid,
                technicalMessage: "帧尺寸不一致，无法转 GIF"
            ))
        }
    }

    func testValidateFrameDimensionsReportsOutputValidationFailureForUnreadableHeaders() throws {
        let readable = try makePNG(named: "frame_0001.png", width: 12, height: 8)
        let unreadable = directory.appendingPathComponent("frame_0002.png")
        try Data("not a PNG".utf8).write(to: unreadable)
        let sequence = PNGSequence(
            frameURLs: [readable, unreadable],
            importedFolderRoot: directory,
            outputFileName: "frame.gif"
        )

        XCTAssertThrowsError(try PNGSequenceDetector().validateFrameDimensions(sequence)) { error in
            XCTAssertEqual(error as? CompressionFailure, CompressionFailure(
                code: .outputInvalid,
                technicalMessage: "帧尺寸不一致，无法转 GIF"
            ))
        }
    }

    private func discoveredFile(named name: String, in folder: URL? = nil) throws -> DiscoveredImage {
        let parent = folder ?? directory!
        let url = parent.appendingPathComponent(name)
        try Data().write(to: url)
        return DiscoveredImage(fileURL: url, importedFolderRoot: directory)
    }

    private func makePNG(named name: String, width: Int, height: Int) throws -> URL {
        let url = directory.appendingPathComponent(name)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}
