import Foundation

enum OutputPolicy: Equatable {
    case adjacent
    case customDirectory
    case overwrite

    func prepare(
        source: URL,
        customDirectory: URL? = nil,
        reservedFinalURLs: Set<URL> = []
    ) throws -> PreparedOutput {
        let sourceURL = source.standardizedFileURL
        let finalURL: URL

        switch self {
        case .adjacent:
            finalURL = availableOutputURL(
                in: sourceURL.deletingLastPathComponent(),
                source: sourceURL,
                reservedFinalURLs: reservedFinalURLs
            )
        case .customDirectory:
            guard let customDirectory else {
                throw OutputPolicyError.customDirectoryRequired
            }

            let directory = customDirectory.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) else {
                throw OutputPolicyError.customDirectoryDoesNotExist(directory)
            }
            guard isDirectory.boolValue else {
                throw OutputPolicyError.customDestinationIsNotDirectory(directory)
            }
            finalURL = availableOutputURL(
                in: directory,
                source: sourceURL,
                reservedFinalURLs: reservedFinalURLs
            )
        case .overwrite:
            finalURL = sourceURL
        }

        return PreparedOutput(
            finalURL: finalURL,
            temporaryURL: temporarySibling(of: finalURL),
            allowsReplacingExistingFile: self == .overwrite
        )
    }

    private func availableOutputURL(
        in directory: URL,
        source: URL,
        reservedFinalURLs: Set<URL>
    ) -> URL {
        let reservedDestinationKeys = Set(reservedFinalURLs.map(destinationKey(for:)))
        let baseName = "\(source.deletingPathExtension().lastPathComponent)-optimized"
        let sourceExtension = source.pathExtension.lowercased()
        var suffix = 1

        while true {
            let filename = suffix == 1
                ? "\(baseName).\(sourceExtension)"
                : "\(baseName)-\(suffix).\(sourceExtension)"
            let candidate = directory.appendingPathComponent(filename).standardizedFileURL
            if !reservedDestinationKeys.contains(destinationKey(for: candidate)), !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            suffix += 1
        }
    }

    /// Destination volumes are commonly case-insensitive APFS. Reserving with
    /// a case-folded path avoids planning two outputs for the same file.
    private func destinationKey(for url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }

    private func temporarySibling(of finalURL: URL) -> URL {
        let filename = finalURL.lastPathComponent
        let fileExtension = finalURL.pathExtension.lowercased()
        let temporaryName = ".\(filename).ffpng-\(UUID().uuidString).tmp.\(fileExtension)"
        return finalURL.deletingLastPathComponent().appendingPathComponent(temporaryName)
    }
}

enum OutputPolicyError: Error, Equatable {
    case customDirectoryRequired
    case customDirectoryDoesNotExist(URL)
    case customDestinationIsNotDirectory(URL)
    case destinationAlreadyExists(URL)
}

struct PreparedOutput: Equatable {
    let finalURL: URL
    let temporaryURL: URL
    let allowsReplacingExistingFile: Bool

    init(
        finalURL: URL,
        temporaryURL: URL,
        allowsReplacingExistingFile: Bool = true
    ) {
        self.finalURL = finalURL.standardizedFileURL
        self.temporaryURL = temporaryURL.standardizedFileURL
        self.allowsReplacingExistingFile = allowsReplacingExistingFile
    }

    func commit(using fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: finalURL.path) {
            guard allowsReplacingExistingFile else {
                throw OutputPolicyError.destinationAlreadyExists(finalURL)
            }
            _ = try fileManager.replaceItemAt(finalURL, withItemAt: temporaryURL)
        } else {
            try fileManager.moveItem(at: temporaryURL, to: finalURL)
        }
    }
}
