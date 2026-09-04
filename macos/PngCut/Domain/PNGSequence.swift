import Foundation

struct PNGSequence: Equatable, Sendable {
    let frameURLs: [URL]
    let importedFolderRoot: URL?
    let outputFileName: String

    init(frameURLs: [URL], importedFolderRoot: URL?, outputFileName: String) {
        self.frameURLs = frameURLs.map(\.standardizedFileURL)
        self.importedFolderRoot = importedFolderRoot?.standardizedFileURL
        self.outputFileName = outputFileName
    }
}
