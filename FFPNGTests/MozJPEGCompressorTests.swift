import XCTest
@testable import FFPNG

final class MozJPEGCompressorTests: XCTestCase {
    func testResolverChoosesX8664BundledHelper() throws {
        let directory = try makeDirectory()
        let helper = directory.appendingPathComponent("mozjpeg-helper-x86_64")
        try makeExecutable(at: helper, script: "#!/bin/sh\nexit 0\n")

        let resolver = MozJPEGBinaryResolver(resourceDirectory: directory, architecture: .x86_64)
        XCTAssertEqual(try resolver.executableURL(), helper)
    }

    func testCompressorRunsHelperWithSourceAndTemporaryDestination() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("fake-mozjpeg")
        try makeExecutable(at: executable, script: """
        #!/bin/sh
        [ "$1" = "--quality" ] || exit 10
        [ "$2" = "75" ] || exit 11
        [ "$3" = "--output" ] || exit 12
        [ "$5" = "--preserve-metadata" ] || exit 13
        printf 'jpeg' > "$4"
        """)
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("temporary.jpg")
        try Data("source".utf8).write(to: source)

        try await MozJPEGCompressor(resolver: MozJPEGFixedResolver(url: executable)).compress(
            source: source,
            temporaryDestination: destination,
            progress: { _ in }
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("jpeg".utf8))
    }

    func testCompressorMapsProcessFailureToLocalExecution() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("failing-mozjpeg")
        try makeExecutable(at: executable, script: "#!/bin/sh\nprintf 'invalid JPEG' >&2\nexit 8\n")

        do {
            try await MozJPEGCompressor(resolver: MozJPEGFixedResolver(url: executable)).compress(
                source: directory.appendingPathComponent("source.jpg"),
                temporaryDestination: directory.appendingPathComponent("temporary.jpg"),
                progress: { _ in }
            )
            XCTFail("Expected a process failure")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure, .localExecution("invalid JPEG"))
        }
    }

    func testCompressorMapsEmptySuccessfulOutputToOutputValidation() async throws {
        let directory = try makeDirectory()
        let executable = directory.appendingPathComponent("empty-mozjpeg")
        try makeExecutable(at: executable, script: "#!/bin/sh\nprintf '' > \"$4\"\n")

        do {
            try await MozJPEGCompressor(resolver: MozJPEGFixedResolver(url: executable)).compress(
                source: directory.appendingPathComponent("source.jpg"),
                temporaryDestination: directory.appendingPathComponent("temporary.jpg"),
                progress: { _ in }
            )
            XCTFail("Expected output validation to fail")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure, .outputValidation("MozJPEG did not create a non-empty output file."))
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MozJPEGCompressorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeExecutable(at url: URL, script: String) throws {
        try Data(script.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

private struct MozJPEGFixedResolver: MozJPEGBinaryResolving {
    let url: URL
    func executableURL() throws -> URL { url }
}
