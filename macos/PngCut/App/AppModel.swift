import AppKit
import Combine
import Foundation

enum CompressionMode: String, CaseIterable, Equatable {
    case lossless
    case balanced

    var title: String {
        switch self {
        case .lossless: "无损"
        case .balanced: "平衡"
        }
    }
}

struct AppSettings: Equatable {
    var mode: CompressionMode = .lossless
    var outputPolicy: OutputPolicy = .adjacent
    var customOutputDirectory: URL?
}

private func makeDefaultCompressor(for engine: CompressionEngine) -> any ImageCompressor {
    switch engine {
    case .oxipng:
        OxipngCompressor()
    case .pngquant:
        PngquantCompressor()
    case .mozjpeg:
        MozJPEGCompressor()
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist(settings) }
    }
    @Published private(set) var tasks: [CompressionTask]
    @Published private(set) var skippedNonPNGCount = 0

    private let fileDiscovery: FileDiscovery
    private let preferences: UserDefaults
    private let compressorFactory: (CompressionEngine) -> any ImageCompressor
    private var queue: CompressionQueue?
    private var enqueueTail: Task<Void, Never>?
    private var reservedOutputURLs: Set<URL>

    init(
        settings: AppSettings = AppSettings(),
        tasks: [CompressionTask] = [],
        fileDiscovery: FileDiscovery = FileDiscovery(),
        preferences: UserDefaults = .standard,
        loadPersistedSettings: Bool = true,
        compressorFactory: @escaping (CompressionEngine) -> any ImageCompressor = makeDefaultCompressor
    ) {
        self.preferences = preferences
        self.settings = loadPersistedSettings ? Self.loadSettings(from: preferences) : settings
        self.tasks = tasks
        self.fileDiscovery = fileDiscovery
        self.compressorFactory = compressorFactory
        self.reservedOutputURLs = Set(tasks.compactMap(\.outputURL))
    }

    static func preview() -> AppModel {
        AppModel(loadPersistedSettings: false)
    }

    var hasCompletedOutput: Bool {
        tasks.contains { $0.state == .completed && $0.outputURL != nil }
    }

    var lastCompletedOutput: URL? {
        tasks.last { $0.state == .completed && $0.outputURL != nil }?.outputURL
    }

    func add(urls: [URL]) {
        let discovery = fileDiscovery.discover(urls: urls)
        skippedNonPNGCount += discovery.skippedNonPNGCount
        let discovered = discovery.images
        guard !discovered.isEmpty else { return }

        var prepared: [CompressionQueue.WorkItem] = []
        var failed: [CompressionQueue.WorkItem] = []
        var outputPlanner = OutputPlanner(
            policy: settings.outputPolicy,
            customDirectory: settings.customOutputDirectory,
            reservedFinalURLs: reservedOutputURLs
        )
        for discoveredImage in discovered {
            let sourceURL = discoveredImage.fileURL
            let configuration = compressionConfiguration(for: ImageFormat(url: sourceURL)!)
            let compressor = compressorFactory(configuration.engine)
            do {
                let output = try outputPlanner.prepare(
                    source: sourceURL,
                    importedFolderRoot: discoveredImage.importedFolderRoot
                )
                prepared.append(
                    CompressionQueue.WorkItem(task: CompressionTask(
                        sourceURL: sourceURL,
                        outputURL: output.finalURL,
                        temporaryOutputURL: output.temporaryURL,
                        allowsReplacingExistingOutput: output.allowsReplacingExistingFile,
                        originalFileSize: fileSize(at: sourceURL),
                        format: ImageFormat(url: sourceURL),
                        engine: configuration.engine,
                        displayMode: configuration.displayMode
                    ), compressor: compressor)
                )
            } catch {
                failed.append(
                    CompressionQueue.WorkItem(task: CompressionTask(
                        sourceURL: sourceURL,
                        state: .failed(.outputValidation(error.localizedDescription)),
                        format: ImageFormat(url: sourceURL),
                        engine: configuration.engine,
                        displayMode: configuration.displayMode
                    ), compressor: compressor)
                )
            }
        }
        reservedOutputURLs = outputPlanner.plannedFinalURLs

        startQueue(with: prepared, failed: failed)
    }

    func retryFailed() {
        Task { [weak self] in
            guard let self, let queue else { return }
            await queue.retryFailed()
        }
    }

    func revealOutput() {
        if settings.outputPolicy == .customDirectory,
           let directory = settings.customOutputDirectory {
            NSWorkspace.shared.open(directory)
            return
        }
        guard let output = lastCompletedOutput else { return }
        NSWorkspace.shared.activateFileViewerSelecting([output])
    }

    func setCompressionMode(_ mode: CompressionMode) {
        settings.mode = mode
    }

    private func startQueue(with preparedTasks: [CompressionQueue.WorkItem], failed failedTasks: [CompressionQueue.WorkItem]) {
        guard let firstCompressor = (preparedTasks + failedTasks).first?.compressor else { return }
        let queue = existingOrNewQueue(defaultCompressor: firstCompressor)

        let previousEnqueue = enqueueTail
        let enqueue = Task {
            await previousEnqueue?.value
            await queue.recordFailed(failedTasks)
            await queue.enqueue(preparedTasks)
        }
        enqueueTail = enqueue
    }

    private func existingOrNewQueue(defaultCompressor: any ImageCompressor) -> CompressionQueue {
        if let queue {
            return queue
        }
        let queue = CompressionQueue(compressor: defaultCompressor) { [weak self] tasks in
            self?.tasks = tasks
        }
        self.queue = queue
        return queue
    }

    private func compressionConfiguration(for format: ImageFormat) -> (engine: CompressionEngine, displayMode: CompressionMode) {
        switch format {
        case .png:
            switch settings.mode {
            case .lossless: (.oxipng, .lossless)
            case .balanced: (.pngquant, .balanced)
            }
        case .jpeg:
            (.mozjpeg, .balanced)
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(value)
    }

    private func persist(_ settings: AppSettings) {
        preferences.set(settings.outputPolicy.persistenceValue, forKey: PreferenceKey.outputPolicy)
        preferences.set(settings.mode.rawValue, forKey: PreferenceKey.compressionMode)
        preferences.set(settings.customOutputDirectory?.path, forKey: PreferenceKey.customOutputDirectory)
    }

    private static func loadSettings(from preferences: UserDefaults) -> AppSettings {
        let storedDirectory = preferences.string(forKey: PreferenceKey.customOutputDirectory).flatMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : nil
        }
        let policy = OutputPolicy(persistenceValue: preferences.string(forKey: PreferenceKey.outputPolicy))
        let mode = CompressionMode(rawValue: preferences.string(forKey: PreferenceKey.compressionMode) ?? "") ?? .lossless
        return AppSettings(
            mode: mode,
            outputPolicy: policy == .customDirectory && storedDirectory == nil ? .adjacent : policy,
            customOutputDirectory: storedDirectory
        )
    }
}

private enum PreferenceKey {
    static let outputPolicy = "pngcut.output-policy"
    static let compressionMode = "pngcut.compression-mode"
    static let customOutputDirectory = "pngcut.custom-output-directory"
}

private extension OutputPolicy {
    var persistenceValue: String {
        switch self {
        case .adjacent: "adjacent"
        case .customDirectory: "customDirectory"
        case .overwrite: "overwrite"
        }
    }

    init(persistenceValue: String?) {
        switch persistenceValue {
        case "customDirectory": self = .customDirectory
        case "overwrite": self = .overwrite
        default: self = .adjacent
        }
    }
}
