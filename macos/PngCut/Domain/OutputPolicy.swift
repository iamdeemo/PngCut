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
        var planner = OutputPlanner(
            policy: self,
            customDirectory: customDirectory,
            reservedFinalURLs: reservedFinalURLs
        )
        return try planner.prepare(source: source)
    }
}

struct OutputPlanner {
    private let policy: OutputPolicy
    private let customDirectory: URL?
    private var reservedFinalURLs: Set<URL>
    private var folderDestinations: [String: URL] = [:]
    private var reservedFolderDestinationKeys: Set<String> = []

    init(policy: OutputPolicy, customDirectory: URL?, reservedFinalURLs: Set<URL>) {
        self.policy = policy
        self.customDirectory = customDirectory
        self.reservedFinalURLs = reservedFinalURLs
    }

    var plannedFinalURLs: Set<URL> { reservedFinalURLs }

    mutating func prepare(
        source: URL,
        importedFolderRoot: URL? = nil
    ) throws -> PreparedOutput {
        let sourceURL = source.standardizedFileURL
        let finalURL: URL

        switch policy {
        case .adjacent:
            if let importedFolderRoot,
               let destination = try folderDestination(for: sourceURL, importedFolderRoot: importedFolderRoot) {
                finalURL = destination
            } else {
                finalURL = availableOutputURL(in: sourceURL.deletingLastPathComponent(), source: sourceURL)
            }
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
            finalURL = availableOutputURL(in: directory, source: sourceURL)
        case .overwrite:
            finalURL = sourceURL
        }

        let prepared = PreparedOutput(
            finalURL: finalURL,
            temporaryURL: temporarySibling(of: finalURL),
            allowsReplacingExistingFile: policy == .overwrite
        )
        reservedFinalURLs.insert(prepared.finalURL)
        return prepared
    }

    private mutating func folderDestination(for source: URL, importedFolderRoot: URL) throws -> URL? {
        let root = importedFolderRoot.standardizedFileURL
        let rootComponents = root.pathComponents
        let sourceComponents = source.pathComponents
        guard sourceComponents.count > rootComponents.count,
              Array(sourceComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }

        let rootKey = destinationKey(for: root)
        let destinationRoot: URL
        if let existingDestination = folderDestinations[rootKey] {
            destinationRoot = existingDestination
        } else {
            destinationRoot = availableFolderURL(
                beside: root,
                name: "\(root.lastPathComponent)_pngcut"
            )
            folderDestinations[rootKey] = destinationRoot
            reservedFolderDestinationKeys.insert(destinationKey(for: destinationRoot))
        }

        return sourceComponents.dropFirst(rootComponents.count).reduce(destinationRoot) { partialResult, component in
            partialResult.appendingPathComponent(component)
        }
    }

    private func availableOutputURL(
        in directory: URL,
        source: URL
    ) -> URL {
        let reservedDestinationKeys = Set(reservedFinalURLs.map(destinationKey(for:)))
        let baseName = "\(source.deletingPathExtension().lastPathComponent)_pngcut"
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

    private func availableFolderURL(beside root: URL, name: String) -> URL {
        let parentDirectory = root.deletingLastPathComponent()
        var suffix = 1

        while true {
            let folderName = suffix == 1 ? name : "\(name)-\(suffix)"
            let candidate = parentDirectory.appendingPathComponent(folderName, isDirectory: true).standardizedFileURL
            let candidateKey = destinationKey(for: candidate)
            let hasReservedOutputInside = reservedFinalURLs.contains { output in
                output.path.lowercased().hasPrefix("\(candidate.path.lowercased())/")
            }
            if !reservedFolderDestinationKeys.contains(candidateKey),
               !hasReservedOutputInside,
               !FileManager.default.fileExists(atPath: candidate.path) {
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
        let temporaryName = ".\(filename).pngcut-\(UUID().uuidString).tmp.\(fileExtension)"
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
        try fileManager.createDirectory(
            at: finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
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
