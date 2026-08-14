import Foundation

enum CompressionEngine: String, Equatable, Sendable {
    case oxipng
    case pngquant
    case mozjpeg
}

struct CompressionTask: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    let format: ImageFormat
    let engine: CompressionEngine
    let displayMode: CompressionMode
    var outputURL: URL?
    var temporaryOutputURL: URL?
    let allowsReplacingExistingOutput: Bool
    /// Captured before processing so an overwrite task can still report its
    /// original size after the source path is atomically replaced.
    let originalFileSize: Int64?
    var state: CompressionTaskState
    var progress: Double

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        outputURL: URL? = nil,
        temporaryOutputURL: URL? = nil,
        allowsReplacingExistingOutput: Bool = true,
        originalFileSize: Int64? = nil,
        state: CompressionTaskState = .queued,
        progress: Double = 0,
        format: ImageFormat? = nil,
        engine: CompressionEngine = .oxipng,
        displayMode: CompressionMode = .lossless
    ) {
        self.id = id
        self.sourceURL = sourceURL.standardizedFileURL
        self.format = format ?? ImageFormat(url: sourceURL) ?? .png
        self.engine = engine
        self.displayMode = displayMode
        self.outputURL = outputURL?.standardizedFileURL
        self.temporaryOutputURL = temporaryOutputURL?.standardizedFileURL
        self.allowsReplacingExistingOutput = allowsReplacingExistingOutput
        self.originalFileSize = originalFileSize
        self.state = state
        self.progress = progress
    }
}

enum CompressionTaskState: Equatable {
    case queued
    case processing
    case completed
    case failed(CompressionFailure)

    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
}
