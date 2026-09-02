import Foundation

protocol GifskiBinaryResolving: Sendable {
    func executableURL() throws -> URL
}

protocol GifskiSequenceEncoding: Sendable {
    func encode(
        frames: [URL],
        temporaryDestination: URL,
        quality: Int,
        frameRate: Int,
        loop: GIFLoop,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

struct GifskiBinaryResolver: GifskiBinaryResolving, Sendable {
    let resourceDirectory: URL
    let architecture: BundledExecutableArchitecture

    init(resourceDirectory: URL, architecture: BundledExecutableArchitecture = .current) {
        self.resourceDirectory = resourceDirectory
        self.architecture = architecture
    }

    init(bundle: Bundle = .main, architecture: BundledExecutableArchitecture = .current) {
        self.init(
            resourceDirectory: (bundle.resourceURL ?? bundle.bundleURL)
                .appendingPathComponent("gifski", isDirectory: true),
            architecture: architecture
        )
    }

    func executableURL() throws -> URL {
        try BundledExecutableResolver(
            resourceDirectory: resourceDirectory,
            executableBaseName: "gifski",
            architecture: architecture
        ).executableURL()
    }
}

struct GifskiSequenceEncoder: GifskiSequenceEncoding, Sendable {
    private let resolver: any GifskiBinaryResolving

    init(resolver: any GifskiBinaryResolving = GifskiBinaryResolver()) {
        self.resolver = resolver
    }

    func encode(
        frames: [URL],
        temporaryDestination: URL,
        quality: Int,
        frameRate: Int,
        loop: GIFLoop,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        progress(0)
        try validate(quality: quality, frameRate: frameRate, frames: frames)

        let result = try LocalProcessRunner.run(
            executable: try resolver.executableURL(),
            arguments: [
                "--quality", String(quality),
                "--fps", String(frameRate),
                "--repeat", String(loop.gifskiRepeatArgument),
                "--output", temporaryDestination.path,
                "--no-sort"
            ] + frames.map(\.path),
            toolName: "gifski"
        )
        guard result.status == 0 else {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CompressionFailure(
                code: .engineFailed,
                technicalMessage: detail.isEmpty ? "gifski exited with status \(result.status)." : detail
            )
        }

        try LocalProcessRunner.validateNonEmptyRegularFile(
            at: temporaryDestination,
            missingMessage: "gifski did not create an output file.",
            emptyMessage: "gifski created an empty output file."
        )
        progress(1)
    }

    private func validate(quality: Int, frameRate: Int, frames: [URL]) throws {
        guard (1...100).contains(quality) else {
            throw CompressionFailure(
                code: .inputUnreadable,
                technicalMessage: "gifski quality must be between 1 and 100."
            )
        }
        guard (1...50).contains(frameRate) else {
            throw CompressionFailure(
                code: .inputUnreadable,
                technicalMessage: "gifski frame rate must be between 1 and 50."
            )
        }
        guard frames.count >= 10 else {
            throw CompressionFailure(
                code: .inputUnreadable,
                technicalMessage: "gifski requires at least 10 frames."
            )
        }
    }
}
