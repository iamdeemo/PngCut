import XCTest
@testable import FFPNG

final class PngquantCompressorTests: XCTestCase {
    func testResolverChoosesArm64BundledBinary() throws {
        let directory = try makeDirectory()
        let binary = directory.appendingPathComponent("pngquant-arm64")
        try makeExecutable(at: binary, script: "#!/bin/sh\nexit 0\n")

        let resolver = PngquantBinaryResolver(resourceDirectory: directory, architecture: .arm64)
        XCTAssertEqual(try resolver.executableURL(), binary)
    }

    func testCompressorRunsExpectedCommandAndValidatesOutput() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("fake-pngquant")
        try makeExecutable(at: executable, script: """
        #!/bin/sh
        [ "$1" = "--quality=65-80" ] || exit 10
        [ "$2" = "--speed" ] || exit 11
        [ "$3" = "4" ] || exit 12
        [ "$4" = "--skip-if-larger" ] || exit 13
        [ "$5" = "--output" ] || exit 14
        printf 'png' > "$6"
        """)
        let source = directory.appendingPathComponent("source.png")
        let destination = directory.appendingPathComponent("temporary.png")
        try Data("source".utf8).write(to: source)

        try await PngquantCompressor(resolver: PngquantFixedResolver(url: executable)).compress(
            source: source,
            temporaryDestination: destination,
            progress: { _ in }
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("png".utf8))
    }

    func testCompressorCopiesSourceWhenPngquantExits99() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("unchanged-pngquant")
        try makeExecutable(at: executable, script: "#!/bin/sh\nexit 99\n")
        let source = directory.appendingPathComponent("source.png")
        let destination = directory.appendingPathComponent("temporary.png")
        try Data("original PNG".utf8).write(to: source)

        try await PngquantCompressor(resolver: PngquantFixedResolver(url: executable)).compress(
            source: source,
            temporaryDestination: destination,
            progress: { _ in }
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("original PNG".utf8))
    }

    func testCompressorMapsProcessFailureToLocalExecution() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("failing-pngquant")
        try makeExecutable(at: executable, script: "#!/bin/sh\nprintf 'invalid PNG' >&2\nexit 7\n")

        do {
            try await PngquantCompressor(resolver: PngquantFixedResolver(url: executable)).compress(
                source: directory.appendingPathComponent("source.png"),
                temporaryDestination: directory.appendingPathComponent("temporary.png"),
                progress: { _ in }
            )
            XCTFail("Expected a process failure")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure, .localExecution("invalid PNG"))
        }
    }

    func testCompressorMapsMissingSuccessfulOutputToOutputValidation() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("silent-pngquant")
        try makeExecutable(at: executable, script: "#!/bin/sh\nexit 0\n")

        do {
            try await PngquantCompressor(resolver: PngquantFixedResolver(url: executable)).compress(
                source: directory.appendingPathComponent("source.png"),
                temporaryDestination: directory.appendingPathComponent("temporary.png"),
                progress: { _ in }
            )
            XCTFail("Expected output validation to fail")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure, .outputValidation("pngquant did not create an output file."))
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PngquantCompressorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeExecutable(at url: URL, script: String) throws {
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private struct PngquantFixedResolver: PngquantBinaryResolving {
    let url: URL
    func executableURL() throws -> URL { url }
}
