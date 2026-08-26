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

struct DiscoveredImage: Equatable {
    let fileURL: URL
    /// Non-nil only when the image was discovered beneath a directory the user selected.
    let importedFolderRoot: URL?
}

struct FileDiscoveryResult: Equatable {
    let images: [DiscoveredImage]
    let skippedNonImageCount: Int

    var files: [URL] { images.map(\.fileURL) }

    /// Temporary compatibility for callers that still present this as a PNG-only app.
    var skippedNonPNGCount: Int { skippedNonImageCount }
}

struct FileDiscovery {
    func discover(urls: [URL]) -> FileDiscoveryResult {
        var images: [DiscoveredImage] = []
        var seenFiles = Set<URL>()
        var visitedDirectories = Set<URL>()
        var skippedNonImageCount = 0

        func inspect(_ candidate: URL, importedFolderRoot: URL? = nil) {
            let fileURL = candidate.standardizedFileURL
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else {
                return
            }
            guard seenFiles.insert(fileURL).inserted else {
                return
            }

            if ImageFormat(url: fileURL) != nil {
                images.append(DiscoveredImage(fileURL: fileURL, importedFolderRoot: importedFolderRoot))
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
                inspect(fileURL, importedFolderRoot: directoryURL)
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

        return FileDiscoveryResult(images: images, skippedNonImageCount: skippedNonImageCount)
    }
}
