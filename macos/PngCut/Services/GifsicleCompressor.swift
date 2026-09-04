import Foundation

protocol GifsicleBinaryResolving: Sendable {
    func executableURL() throws -> URL
}

struct GifsicleBinaryResolver: GifsicleBinaryResolving, Sendable {
    let resourceDirectory: URL
    let architecture: BundledExecutableArchitecture

    init(resourceDirectory: URL, architecture: BundledExecutableArchitecture = .current) {
        self.resourceDirectory = resourceDirectory
        self.architecture = architecture
    }

    init(bundle: Bundle = .main, architecture: BundledExecutableArchitecture = .current) {
        self.init(
            resourceDirectory: (bundle.resourceURL ?? bundle.bundleURL)
                .appendingPathComponent("gifsicle", isDirectory: true),
            architecture: architecture
        )
    }

    func executableURL() throws -> URL {
        try BundledExecutableResolver(
            resourceDirectory: resourceDirectory,
            executableBaseName: "gifsicle",
            architecture: architecture
        ).executableURL()
    }
}

struct GifsicleCompressor: ImageCompressor, Sendable {
    private let mode: CompressionMode
    private let resolver: any GifsicleBinaryResolving

    init(
        mode: CompressionMode,
        resolver: any GifsicleBinaryResolving = GifsicleBinaryResolver()
    ) {
        self.mode = mode
        self.resolver = resolver
    }

    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        progress(0)
        let result = try LocalProcessRunner.run(
            executable: try resolver.executableURL(),
            arguments: arguments(source: source, temporaryDestination: temporaryDestination),
            toolName: "gifsicle"
        )
        guard result.status == 0 else {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CompressionFailure(
                code: .engineFailed,
                technicalMessage: detail.isEmpty ? "gifsicle exited with status \(result.status)." : detail
            )
        }

        try LocalProcessRunner.validateNonEmptyRegularFile(
            at: temporaryDestination,
            missingMessage: "gifsicle did not create an output file.",
            emptyMessage: "gifsicle created an empty output file."
        )

        let temporarySize = try fileSize(at: temporaryDestination)
        let sourceSize = try fileSize(at: source)
        guard temporarySize < sourceSize else {
            try FileManager.default.removeItem(at: temporaryDestination)
            progress(1)
            return .noChange
        }

        progress(1)
        return .compressed
    }

    private func arguments(source: URL, temporaryDestination: URL) -> [String] {
        let modeArguments: [String]
        switch mode {
        case .lossless:
            modeArguments = ["-O3"]
        case .balanced:
            modeArguments = ["-O3", "--lossy=200"]
        }
        return modeArguments + ["--output", temporaryDestination.path, source.path]
    }

    private func fileSize(at url: URL) throws -> Int {
        do {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                throw CompressionFailure(
                    code: .inputUnreadable,
                    technicalMessage: "Unable to determine the size of \(url.lastPathComponent)."
                )
            }
            return size
        } catch let failure as CompressionFailure {
            throw failure
        } catch {
            throw CompressionFailure(
                code: .inputUnreadable,
                technicalMessage: "Unable to determine the size of \(url.lastPathComponent)."
            )
        }
    }
}
