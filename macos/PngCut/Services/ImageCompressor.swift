import Foundation

protocol ImageCompressor: Sendable {
    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome
}

enum CompressionOutcome: Equatable, Sendable {
    case compressed
    case noChange
}

enum CompressionOperation: Sendable {
    case file(any ImageCompressor)
    case pngSequence(any GifskiSequenceEncoding, quality: Int, frameRate: Int, loop: GIFLoop)

    func run(
        task: CompressionTask,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        switch self {
        case .file(let compressor):
            return try await compressor.compress(
                source: task.sourceURL,
                temporaryDestination: temporaryDestination,
                progress: progress
            )
        case let .pngSequence(encoder, quality, frameRate, loop):
            try await encoder.encode(
                frames: task.sourceURLs,
                temporaryDestination: temporaryDestination,
                quality: quality,
                frameRate: frameRate,
                loop: loop,
                progress: progress
            )
            return .compressed
        }
    }
}

struct CompressionFailure: Error, Equatable, Sendable {
    let code: FailureCode
    let technicalMessage: String?
}

enum BundledExecutableArchitecture: String, Sendable, Equatable {
    case arm64
    case x86_64

    init(machineIdentifier: String) {
        switch machineIdentifier.lowercased() {
        case "arm64", "arm64e": self = .arm64
        default: self = .x86_64
        }
    }

    static var current: Self {
        var system = utsname()
        uname(&system)
        let identifier = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return Self(machineIdentifier: identifier)
    }
}

struct BundledExecutableResolver: Sendable {
    let resourceDirectory: URL
    let executableBaseName: String
    let architecture: BundledExecutableArchitecture

    init(resourceDirectory: URL, executableBaseName: String, architecture: BundledExecutableArchitecture = .current) {
        self.resourceDirectory = resourceDirectory
        self.executableBaseName = executableBaseName
        self.architecture = architecture
    }

    func executableURL() throws -> URL {
        let name = "\(executableBaseName)-\(architecture.rawValue)"
        let url = resourceDirectory.appendingPathComponent(name, isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CompressionFailure(
                code: .engineUnavailable,
                technicalMessage: "Bundled \(name) executable is unavailable."
            )
        }
        return url
    }
}

struct LocalProcessResult: Sendable {
    let status: Int32
    let standardError: String
}

enum LocalProcessRunner {
    static func run(executable: URL, arguments: [String], toolName: String) throws -> LocalProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let standardError = Pipe()
        process.standardError = standardError
        let capture = StandardErrorCapture(fileHandle: standardError.fileHandleForReading)
        do {
            try process.run()
            standardError.fileHandleForWriting.closeFile()
        } catch {
            standardError.fileHandleForWriting.closeFile()
            _ = capture.finish()
            throw CompressionFailure(
                code: .engineFailed,
                technicalMessage: "Unable to start \(toolName): \(error.localizedDescription)"
            )
        }

        process.waitUntilExit()
        return LocalProcessResult(status: process.terminationStatus, standardError: capture.finish())
    }

    static func validateNonEmptyRegularFile(at url: URL, missingMessage: String, emptyMessage: String) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw CompressionFailure(code: .outputInvalid, technicalMessage: missingMessage)
        }
        guard values.isRegularFile == true else {
            throw CompressionFailure(code: .outputInvalid, technicalMessage: missingMessage)
        }
        guard (values.fileSize ?? 0) > 0 else {
            throw CompressionFailure(code: .outputInvalid, technicalMessage: emptyMessage)
        }
    }
}

/// Drains child stderr separately so large diagnostic output cannot block it.
private final class StandardErrorCapture: @unchecked Sendable {
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()

    init(fileHandle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.group.leave() }
            let captured = (try? fileHandle.readToEnd()) ?? Data()
            self?.lock.lock()
            self?.data = captured
            self?.lock.unlock()
        }
    }

    func finish() -> String {
        group.wait()
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
