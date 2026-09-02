import Foundation
import XCTest
@testable import PngCut

final class GifsicleCompressorTests: XCTestCase {
    func testResolverChoosesArm64BundledBinary() throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("gifsicle-arm64")
        try makeExecutable(at: executable, script: "#!/bin/sh\nexit 0\n")

        let resolver = GifsicleBinaryResolver(resourceDirectory: directory, architecture: .arm64)

        XCTAssertEqual(try resolver.executableURL(), executable)
    }

    func testLosslessCompressorRunsExpectedArgumentsAndReportsProgress() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("fake-gifsicle")
        try makeExecutable(at: executable, script: """
        #!/bin/sh
        [ "$1" = "-O3" ] || exit 10
        [ "$2" = "--output" ] || exit 11
        [ "$4" = "\(directory.appendingPathComponent("source.gif").path)" ] || exit 12
        [ "$#" -eq 4 ] || exit 13
        printf 'gif' > "$3"
        """)
        let source = directory.appendingPathComponent("source.gif")
        let destination = directory.appendingPathComponent("temporary.gif")
        try Data("source GIF bytes".utf8).write(to: source)
        let progress = GifsicleProgressRecorder()

        let outcome = try await GifsicleCompressor(
            mode: .lossless,
            resolver: GifsicleFixedResolver(url: executable)
        ).compress(source: source, temporaryDestination: destination, progress: { value in
            progress.record(value)
        })

        XCTAssertEqual(outcome, .compressed)
        XCTAssertEqual(try Data(contentsOf: destination), Data("gif".utf8))
        XCTAssertEqual(progress.values(), [0, 1])
    }

    func testBalancedCompressorRunsLossyArguments() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("fake-gifsicle")
        try makeExecutable(at: executable, script: """
        #!/bin/sh
        [ "$1" = "-O3" ] || exit 10
        [ "$2" = "--lossy=200" ] || exit 11
        [ "$3" = "--output" ] || exit 12
        [ "$5" = "\(directory.appendingPathComponent("source.gif").path)" ] || exit 13
        [ "$#" -eq 5 ] || exit 14
        printf 'gif' > "$4"
        """)
        let source = directory.appendingPathComponent("source.gif")
        let destination = directory.appendingPathComponent("temporary.gif")
        try Data("source GIF bytes".utf8).write(to: source)

        let outcome = try await GifsicleCompressor(
            mode: .balanced,
            resolver: GifsicleFixedResolver(url: executable)
        ).compress(source: source, temporaryDestination: destination, progress: { _ in })

        XCTAssertEqual(outcome, .compressed)
    }

    func testCompressorMapsProcessFailureWithTrimmedStandardError() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("failing-gifsicle")
        try makeExecutable(at: executable, script: "#!/bin/sh\nprintf ' invalid GIF\\n' >&2\nexit 7\n")

        do {
            _ = try await GifsicleCompressor(
                mode: .lossless,
                resolver: GifsicleFixedResolver(url: executable)
            ).compress(
                source: directory.appendingPathComponent("source.gif"),
                temporaryDestination: directory.appendingPathComponent("temporary.gif"),
                progress: { _ in }
            )
            XCTFail("Expected a process failure")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure.code, .engineFailed)
            XCTAssertEqual(failure.technicalMessage, "invalid GIF")
        }
    }

    func testCompressorMapsEmptySuccessfulOutputToOutputValidation() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("empty-gifsicle")
        try makeExecutable(at: executable, script: "#!/bin/sh\n: > \"$3\"\n")

        do {
            _ = try await GifsicleCompressor(
                mode: .lossless,
                resolver: GifsicleFixedResolver(url: executable)
            ).compress(
                source: directory.appendingPathComponent("source.gif"),
                temporaryDestination: directory.appendingPathComponent("temporary.gif"),
                progress: { _ in }
            )
            XCTFail("Expected output validation to fail")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure.code, .outputInvalid)
            XCTAssertEqual(failure.technicalMessage, "gifsicle created an empty output file.")
        }
    }

    func testCompressorDeletesTemporaryOutputWhenResultIsNotSmaller() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("larger-gifsicle")
        try makeExecutable(at: executable, script: "#!/bin/sh\nprintf 'larger output' > \"$3\"\n")
        let source = directory.appendingPathComponent("source.gif")
        let destination = directory.appendingPathComponent("temporary.gif")
        try Data("small".utf8).write(to: source)

        let outcome = try await GifsicleCompressor(
            mode: .lossless,
            resolver: GifsicleFixedResolver(url: executable)
        ).compress(source: source, temporaryDestination: destination, progress: { _ in })

        XCTAssertEqual(outcome, .noChange)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GifsicleCompressorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeExecutable(at url: URL, script: String) throws {
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private struct GifsicleFixedResolver: GifsicleBinaryResolving {
    let url: URL

    func executableURL() throws -> URL { url }
}

private final class GifsicleProgressRecorder: @unchecked Sendable {
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
