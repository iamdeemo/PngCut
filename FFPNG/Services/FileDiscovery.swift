import Foundation

enum ImageFormat: String, Equatable, Sendable {
    case png
    case jpeg

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "png":
            self = .png
        case "jpg", "jpeg":
            self = .jpeg
        default:
            return nil
        }
    }
}

struct FileDiscoveryResult: Equatable {
    let files: [URL]
    let skippedNonImageCount: Int

    /// Temporary compatibility for callers that still present this as a PNG-only app.
    var skippedNonPNGCount: Int { skippedNonImageCount }
}

struct FileDiscovery {
    func discover(urls: [URL]) -> FileDiscoveryResult {
        var files: [URL] = []
        var seenFiles = Set<URL>()
        var visitedDirectories = Set<URL>()
        var skippedNonImageCount = 0

        func inspect(_ candidate: URL) {
            let fileURL = candidate.standardizedFileURL
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else {
                return
            }
            guard seenFiles.insert(fileURL).inserted else {
                return
            }

            if ImageFormat(url: fileURL) != nil {
                files.append(fileURL)
            } else {
                skippedNonImageCount += 1
            }
        }

        func inspectDirectory(_ directory: URL) {
            let directoryURL = directory.standardizedFileURL
            guard visitedDirectories.insert(directoryURL).inserted,
                  let enumerator = FileManager.default.enumerator(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: []
                  ) else {
                return
            }

            for case let fileURL as URL in enumerator {
                inspect(fileURL)
            }
        }

        for url in urls {
            let candidate = url.standardizedFileURL
            guard let values = try? candidate.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]) else {
                continue
            }

            if values.isDirectory == true {
                inspectDirectory(candidate)
            } else if values.isRegularFile == true {
                inspect(candidate)
            }
        }

        return FileDiscoveryResult(files: files, skippedNonImageCount: skippedNonImageCount)
    }
}
