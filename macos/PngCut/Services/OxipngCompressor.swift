import Foundation

typealias OxipngHostArchitecture = BundledExecutableArchitecture

protocol OxipngBinaryResolving: Sendable {
    func executableURL() throws -> URL
}

struct OxipngBinaryResolver: OxipngBinaryResolving, Sendable {
    let resourceDirectory: URL
    let architecture: OxipngHostArchitecture

    init(
        resourceDirectory: URL,
        architecture: OxipngHostArchitecture = .current
    ) {
        self.resourceDirectory = resourceDirectory
        self.architecture = architecture
    }

    init(bundle: Bundle = .main, architecture: OxipngHostArchitecture = .current) {
        self.init(
            resourceDirectory: (bundle.resourceURL ?? bundle.bundleURL)
                .appendingPathComponent("oxipng", isDirectory: true),
            architecture: architecture
        )
    }

    func executableURL() throws -> URL {
        try BundledExecutableResolver(
            resourceDirectory: resourceDirectory,
            executableBaseName: "oxipng",
            architecture: architecture
        ).executableURL()
    }
}

struct OxipngCompressor: ImageCompressor, Sendable {
    private let resolver: any OxipngBinaryResolving

    init(resolver: any OxipngBinaryResolving = OxipngBinaryResolver()) {
        self.resolver = resolver
    }

    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        progress(0)
        let executable = try resolver.executableURL()
        let result = try LocalProcessRunner.run(
            executable: executable,
            arguments: ["--opt", "2", "--out", temporaryDestination.path, source.path],
            toolName: "oxipng"
        )

        guard result.status == 0 else {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty
                ? "oxipng exited with status \(result.status)."
                : detail
            throw CompressionFailure(code: .engineFailed, technicalMessage: message)
        }

        try LocalProcessRunner.validateNonEmptyRegularFile(
            at: temporaryDestination,
            missingMessage: "oxipng did not create an output file.",
            emptyMessage: "oxipng created an empty output file."
        )
        progress(1)
        return .compressed
    }
}
