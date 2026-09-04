import Foundation

protocol PngquantBinaryResolving: Sendable {
    func executableURL() throws -> URL
}

struct PngquantBinaryResolver: PngquantBinaryResolving, Sendable {
    let resourceDirectory: URL
    let architecture: BundledExecutableArchitecture

    init(resourceDirectory: URL, architecture: BundledExecutableArchitecture = .current) {
        self.resourceDirectory = resourceDirectory
        self.architecture = architecture
    }

    init(bundle: Bundle = .main, architecture: BundledExecutableArchitecture = .current) {
        self.init(
            resourceDirectory: (bundle.resourceURL ?? bundle.bundleURL)
                .appendingPathComponent("pngquant", isDirectory: true),
            architecture: architecture
        )
    }

    func executableURL() throws -> URL {
        try BundledExecutableResolver(
            resourceDirectory: resourceDirectory,
            executableBaseName: "pngquant",
            architecture: architecture
        ).executableURL()
    }
}

struct PngquantCompressor: ImageCompressor, Sendable {
    private let resolver: any PngquantBinaryResolving

    init(resolver: any PngquantBinaryResolving = PngquantBinaryResolver()) {
        self.resolver = resolver
    }

    func compress(source: URL, temporaryDestination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> CompressionOutcome {
        progress(0)
        let result = try LocalProcessRunner.run(
            executable: try resolver.executableURL(),
            arguments: ["--quality=65-80", "--speed", "4", "--skip-if-larger", "--output", temporaryDestination.path, source.path],
            toolName: "pngquant"
        )

        if result.status == 98 || result.status == 99 {
            progress(1)
            return .noChange
        } else if result.status != 0 {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CompressionFailure(
                code: .engineFailed,
                technicalMessage: detail.isEmpty ? "pngquant exited with status \(result.status)." : detail
            )
        }

        try LocalProcessRunner.validateNonEmptyRegularFile(
            at: temporaryDestination,
            missingMessage: "pngquant did not create an output file.",
            emptyMessage: "pngquant created an empty output file."
        )
        progress(1)
        return .compressed
    }
}
