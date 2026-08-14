import XCTest
@testable import FFPNG

final class OxipngCompressorTests: XCTestCase {
    func testResolverChoosesArm64BinaryForAppleSilicon() throws {
        let directory = try makeExecutableDirectory()
        let armBinary = directory.appendingPathComponent("oxipng-arm64")
        FileManager.default.createFile(atPath: armBinary.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: armBinary.path)

        let resolver = OxipngBinaryResolver(resourceDirectory: directory, architecture: .arm64)
        XCTAssertEqual(try resolver.executableURL(), armBinary)
    }

    func testResolverChoosesX8664BinaryForIntelAndRosetta() throws {
        let directory = try makeExecutableDirectory()
        let intelBinary = directory.appendingPathComponent("oxipng-x86_64")
        FileManager.default.createFile(atPath: intelBinary.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: intelBinary.path)

        XCTAssertEqual(OxipngHostArchitecture(machineIdentifier: "x86_64"), .x86_64)
        let resolver = OxipngBinaryResolver(resourceDirectory: directory, architecture: .x86_64)
        XCTAssertEqual(try resolver.executableURL(), intelBinary)
    }

    func testCompressorRunsInjectedExecutableAndValidatesOutput() async throws {
        let directory = try makeExecutableDirectory()
        let executable = directory.appendingPathComponent("fake-oxipng")
        let script = """
        #!/bin/sh
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--out" ]; then
            output="$2"
            shift 2
          else
            shift
          fi
        done
        printf 'png' > "$output"
        """
        FileManager.default.createFile(atPath: executable.path, contents: Data(script.utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let source = directory.appendingPathComponent("source.png")
        let destination = directory.appendingPathComponent("temporary.png")
        FileManager.default.createFile(atPath: source.path, contents: Data("source".utf8))

        let compressor = OxipngCompressor(resolver: FixedResolver(url: executable))
        let progress = ProgressRecorder()
        try await compressor.compress(source: source, temporaryDestination: destination) {
            value in
            progress.append(value)
        }

        XCTAssertEqual(try Data(contentsOf: destination), Data("png".utf8))
        XCTAssertEqual(progress.values(), [0, 1])
    }

    func testCompressorMapsExitFailureToLocalExecution() async throws {
        let directory = try makeExecutableDirectory()
        let executable = directory.appendingPathComponent("failing-oxipng")
        FileManager.default.createFile(
            atPath: executable.path,
            contents: Data("#!/bin/sh\nprintf 'invalid PNG' >&2\nexit 7\n".utf8)
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let compressor = OxipngCompressor(resolver: FixedResolver(url: executable))
        do {
            try await compressor.compress(
                source: directory.appendingPathComponent("source.png"),
                temporaryDestination: directory.appendingPathComponent("temporary.png"),
                progress: { _ in }
            )
            XCTFail("Expected a process failure")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure, .localExecution("invalid PNG"))
        }
    }

    func testCompressorMapsLaunchFailureToLocalExecution() async throws {
        let directory = try makeExecutableDirectory()
        let compressor = OxipngCompressor(
            resolver: FixedResolver(url: directory.appendingPathComponent("missing-oxipng"))
        )

        do {
            try await compressor.compress(
                source: directory.appendingPathComponent("source.png"),
                temporaryDestination: directory.appendingPathComponent("temporary.png"),
                progress: { _ in }
            )
            XCTFail("Expected a launch failure")
        } catch let failure as CompressionFailure {
            guard case let .localExecution(message) = failure else {
                return XCTFail("Expected a local execution failure, got \(failure)")
            }
            XCTAssertTrue(message.hasPrefix("Unable to start oxipng:"))
        }
    }

    func testCompressorMapsMissingSuccessfulOutputToOutputValidation() async throws {
        let directory = try makeExecutableDirectory()
        let executable = directory.appendingPathComponent("silent-oxipng")
        FileManager.default.createFile(atPath: executable.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let compressor = OxipngCompressor(resolver: FixedResolver(url: executable))
        do {
            try await compressor.compress(
                source: directory.appendingPathComponent("source.png"),
                temporaryDestination: directory.appendingPathComponent("temporary.png"),
                progress: { _ in }
            )
            XCTFail("Expected output validation to fail")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure, .outputValidation("oxipng did not create an output file."))
        }
    }

    func testBundledBinaryReportsPinnedVersionWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["FFPNG_RUN_OXIPNG_INTEGRATION_TEST"] == "1" else {
            throw XCTSkip("The bundled-binary integration check is opt-in.")
        }

        let executable = try OxipngBinaryResolver(bundle: Bundle(for: AppModel.self)).executableURL()
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        let version = String(decoding: try output.fileHandleForReading.readToEnd() ?? Data(), as: UTF8.self)
        XCTAssertEqual(version.trimmingCharacters(in: .whitespacesAndNewlines), "oxipng 10.2.0")
    }

    private func makeExecutableDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OxipngCompressorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }
}

private struct FixedResolver: OxipngBinaryResolving {
    let url: URL

    func executableURL() throws -> URL {
        url
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        recordedValues.append(value)
    }

    func values() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}
