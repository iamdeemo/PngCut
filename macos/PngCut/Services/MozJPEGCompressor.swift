import Foundation

protocol MozJPEGBinaryResolving: Sendable {
    func executableURL() throws -> URL
}

struct MozJPEGBinaryResolver: MozJPEGBinaryResolving, Sendable {
    let resourceDirectory: URL
    let architecture: BundledExecutableArchitecture

    init(resourceDirectory: URL, architecture: BundledExecutableArchitecture = .current) {
        self.resourceDirectory = resourceDirectory
        self.architecture = architecture
    }

    init(bundle: Bundle = .main, architecture: BundledExecutableArchitecture = .current) {
        self.init(
            resourceDirectory: (bundle.resourceURL ?? bundle.bundleURL)
                .appendingPathComponent("mozjpeg", isDirectory: true),
            architecture: architecture
        )
    }

    func executableURL() throws -> URL {
        try BundledExecutableResolver(
            resourceDirectory: resourceDirectory,
            executableBaseName: "mozjpeg-helper",
            architecture: architecture
        ).executableURL()
    }
}

struct MozJPEGCompressor: ImageCompressor, Sendable {
    private let resolver: any MozJPEGBinaryResolving

    init(resolver: any MozJPEGBinaryResolving = MozJPEGBinaryResolver()) {
        self.resolver = resolver
    }

    func compress(source: URL, temporaryDestination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> CompressionOutcome {
        progress(0)
        let result = try LocalProcessRunner.run(
            executable: try resolver.executableURL(),
            arguments: ["--quality", "75", "--output", temporaryDestination.path, "--preserve-metadata", source.path],
            toolName: "MozJPEG"
        )
        guard result.status == 0 else {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CompressionFailure(
                code: .engineFailed,
                technicalMessage: detail.isEmpty ? "MozJPEG exited with status \(result.status)." : detail
            )
        }
        try LocalProcessRunner.validateNonEmptyRegularFile(
            at: temporaryDestination,
            missingMessage: "MozJPEG did not create a non-empty output file.",
            emptyMessage: "MozJPEG did not create a non-empty output file."
        )
        progress(1)
        return .compressed
    }
}
