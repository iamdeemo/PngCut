import Foundation
import XCTest
@testable import PngCut

final class GifskiSequenceEncoderTests: XCTestCase {
    func testResolverChoosesX8664BundledBinary() throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("gifski-x86_64")
        try makeExecutable(at: executable, script: "#!/bin/sh\nexit 0\n")

        let resolver = GifskiBinaryResolver(resourceDirectory: directory, architecture: .x86_64)

        XCTAssertEqual(try resolver.executableURL(), executable)
    }

    func testEncoderPreservesFrameOrderAndPassesDefaultQualityPlaybackAndSortingArguments() async throws {
        let directory = try makeDirectory()
        let frames = makeFrames(in: directory, count: 10)
        let destination = directory.appendingPathComponent("temporary.gif")
        let executable = directory.appendingPathComponent("fake-gifski")
        try makeExecutable(at: executable, script: gifskiScript(
            expectedQuality: "100",
            expectedFrameRate: "30",
            expectedRepeat: "0",
            expectedFrames: frames
        ))
        let progress = GifskiProgressRecorder()

        try await GifskiSequenceEncoder(resolver: GifskiFixedResolver(url: executable)).encode(
            frames: frames,
            temporaryDestination: destination,
            quality: 100,
            frameRate: 30,
            loop: .forever,
            progress: { value in progress.record(value) }
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("gif".utf8))
        XCTAssertEqual(progress.values(), [0, 1])
    }

    func testEncoderPassesPlaybackOnceRepeatArgument() async throws {
        let directory = try makeDirectory()
        let frames = makeFrames(in: directory, count: 10)
        let destination = directory.appendingPathComponent("temporary.gif")
        let executable = directory.appendingPathComponent("fake-gifski")
        try makeExecutable(at: executable, script: gifskiScript(
            expectedQuality: "100",
            expectedFrameRate: "30",
            expectedRepeat: "-1",
            expectedFrames: frames
        ))

        try await GifskiSequenceEncoder(resolver: GifskiFixedResolver(url: executable)).encode(
            frames: frames,
            temporaryDestination: destination,
            quality: 100,
            frameRate: 30,
            loop: .once,
            progress: { _ in }
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("gif".utf8))
    }

    func testEncoderRejectsQualityOutsideSupportedRangeBeforeLaunching() async throws {
        let directory = try makeDirectory()
        let frames = makeFrames(in: directory, count: 10)

        await assertInputValidationFailure {
            try await GifskiSequenceEncoder(resolver: GifskiFixedResolver(url: directory.appendingPathComponent("missing-gifski"))).encode(
                frames: frames,
                temporaryDestination: directory.appendingPathComponent("temporary.gif"),
                quality: 0,
                frameRate: 30,
                loop: .forever,
                progress: { _ in }
            )
        }
    }

    func testEncoderRejectsFrameRateOutsideSupportedRangeBeforeLaunching() async throws {
        let directory = try makeDirectory()
        let frames = makeFrames(in: directory, count: 10)

        await assertInputValidationFailure {
            try await GifskiSequenceEncoder(resolver: GifskiFixedResolver(url: directory.appendingPathComponent("missing-gifski"))).encode(
                frames: frames,
                temporaryDestination: directory.appendingPathComponent("temporary.gif"),
                quality: 100,
                frameRate: 51,
                loop: .forever,
                progress: { _ in }
            )
        }
    }

    func testEncoderRejectsSequencesWithFewerThanTenFramesBeforeLaunching() async throws {
        let directory = try makeDirectory()

        await assertInputValidationFailure {
            try await GifskiSequenceEncoder(resolver: GifskiFixedResolver(url: directory.appendingPathComponent("missing-gifski"))).encode(
                frames: makeFrames(in: directory, count: 9),
                temporaryDestination: directory.appendingPathComponent("temporary.gif"),
                quality: 100,
                frameRate: 30,
                loop: .forever,
                progress: { _ in }
            )
        }
    }

    func testEncoderMapsProcessFailureWithTrimmedStandardError() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("failing-gifski")
        try makeExecutable(at: executable, script: "#!/bin/sh\nprintf ' invalid frames\\n' >&2\nexit 9\n")

        do {
            try await GifskiSequenceEncoder(resolver: GifskiFixedResolver(url: executable)).encode(
                frames: makeFrames(in: directory, count: 10),
                temporaryDestination: directory.appendingPathComponent("temporary.gif"),
                quality: 100,
                frameRate: 30,
                loop: .forever,
                progress: { _ in }
            )
            XCTFail("Expected a process failure")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure.code, .engineFailed)
            XCTAssertEqual(failure.technicalMessage, "invalid frames")
        }
    }

    func testEncoderMapsMissingSuccessfulOutputToOutputValidation() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("silent-gifski")
        try makeExecutable(at: executable, script: "#!/bin/sh\nexit 0\n")

        do {
            try await GifskiSequenceEncoder(resolver: GifskiFixedResolver(url: executable)).encode(
                frames: makeFrames(in: directory, count: 10),
                temporaryDestination: directory.appendingPathComponent("temporary.gif"),
                quality: 100,
                frameRate: 30,
                loop: .forever,
                progress: { _ in }
            )
            XCTFail("Expected output validation to fail")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure.code, .outputInvalid)
            XCTAssertEqual(failure.technicalMessage, "gifski did not create an output file.")
        }
    }

    private func assertInputValidationFailure(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected input validation failure")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure.code, .inputUnreadable)
        } catch {
            XCTFail("Expected CompressionFailure, got \(error)")
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GifskiSequenceEncoderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeFrames(in directory: URL, count: Int) -> [URL] {
        (0..<count).map { index in
            directory.appendingPathComponent(String(format: "frame-%02d.png", index))
        }
    }

    private func gifskiScript(
        expectedQuality: String,
        expectedFrameRate: String,
        expectedRepeat: String,
        expectedFrames: [URL]
    ) -> String {
        let frameChecks = expectedFrames.enumerated().map { index, frame in
            "[ \"$1\" = \"\(frame.path)\" ] || exit \(20 + index)\nshift"
        }.joined(separator: "\n")
        return """
        #!/bin/sh
        [ "$1" = "--quality" ] || exit 10
        [ "$2" = "\(expectedQuality)" ] || exit 11
        [ "$3" = "--fps" ] || exit 12
        [ "$4" = "\(expectedFrameRate)" ] || exit 13
        [ "$5" = "--repeat" ] || exit 14
        [ "$6" = "\(expectedRepeat)" ] || exit 15
        [ "$7" = "--output" ] || exit 16
        [ "$9" = "--no-sort" ] || exit 17
        printf 'gif' > "$8"
        shift 9
        \(frameChecks)
        [ "$#" -eq 0 ] || exit 40
        """
    }

    private func makeExecutable(at url: URL, script: String) throws {
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private struct GifskiFixedResolver: GifskiBinaryResolving {
    let url: URL

    func executableURL() throws -> URL { url }
}

private final class GifskiProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []

    func record(_ value: Double) {
        lock.lock()
        recordedValues.append(value)
        lock.unlock()
    }

    func values() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}
