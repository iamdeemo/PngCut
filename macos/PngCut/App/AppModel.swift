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
    var gif: GIFSettings = GIFSettings()
}

struct ImportResolution: Identifiable, Equatable, Sendable {
    let id: UUID
    let regularImages: [DiscoveredImage]
    let sequences: [PNGSequence]
    let totalCandidateFrameCount: Int

    init(
        id: UUID = UUID(),
        regularImages: [DiscoveredImage],
        sequences: [PNGSequence],
        totalCandidateFrameCount: Int? = nil
    ) {
        self.id = id
        self.regularImages = regularImages
        self.sequences = sequences
        self.totalCandidateFrameCount = totalCandidateFrameCount
            ?? sequences.reduce(0) { $0 + $1.frameURLs.count }
    }

    var convertMessage: String {
        "发现达到阈值的连续编号 PNG（共 \(totalCandidateFrameCount) 张），是否转 GIF？"
    }
}

enum ImportPrompt: Identifiable, Equatable, Sendable {
    case convertSequences(ImportResolution)
    case compressWithoutSequence(ImportResolution)

    var id: UUID {
        switch self {
        case let .convertSequences(resolution), let .compressWithoutSequence(resolution):
            resolution.id
        }
    }

    var message: String {
        switch self {
        case let .convertSequences(resolution):
            resolution.convertMessage
        case .compressWithoutSequence:
            "是否按常规方式压缩当前文件？"
        }
    }
}

struct ImportNotice: Identifiable, Equatable, Sendable {
    let id: UUID
    let message: String

    init(id: UUID = UUID(), message: String) {
        self.id = id
        self.message = message
    }
}

private struct ImportDiscoveryResult: Sendable {
    let resolution: ImportResolution
    let skippedNonImageCount: Int
}

private struct SequencePreflightResult: Sendable {
    let sequence: PNGSequence
    let dimensionsAreValid: Bool
}

private func makeDefaultCompressor(
    for engine: CompressionEngine,
    mode: CompressionMode
) -> any ImageCompressor {
    switch engine {
    case .oxipng:
        OxipngCompressor()
    case .pngquant:
        PngquantCompressor()
    case .mozjpeg:
        MozJPEGCompressor()
    case .gifsicle:
        GifsicleCompressor(mode: mode)
    case .gifski:
        UnconfiguredCompressor(engine: engine)
    }
}

private struct UnconfiguredCompressor: ImageCompressor {
    let engine: CompressionEngine

    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        throw CompressionFailure(
            code: .engineUnavailable,
            technicalMessage: "No compressor is configured for \(engine.rawValue)."
        )
    }
}

@MainActor
final class AppModel: ObservableObject {
    typealias CompressorFactory = (CompressionEngine, CompressionMode) -> any ImageCompressor

    @Published var settings: AppSettings {
        didSet { persist(settings) }
    }
    @Published private(set) var tasks: [CompressionTask]
    @Published private(set) var skippedNonPNGCount = 0
    @Published private(set) var pendingImportPrompt: ImportPrompt?
    @Published private(set) var importNotice: ImportNotice?

    private let fileDiscovery: FileDiscovery
    private let sequenceDetector: any PNGSequenceDetecting
    private let sequenceEncoderFactory: () -> any GifskiSequenceEncoding
    private let preferences: UserDefaults
    private let compressorFactory: CompressorFactory
    private var queue: CompressionQueue?
    private var enqueueTail: Task<Void, Never>?
    private var importDiscoveryTail: Task<Void, Never>?
    private var pendingImportResolutions: [ImportResolution] = []
    private var activeImportResolution: ImportResolution?
    private var isPreparingSequenceImport = false
    private var reservedOutputURLs: Set<URL>

    init(
        settings: AppSettings = AppSettings(),
        tasks: [CompressionTask] = [],
        fileDiscovery: FileDiscovery = FileDiscovery(),
        preferences: UserDefaults = .standard,
        loadPersistedSettings: Bool = true,
        sequenceDetector: any PNGSequenceDetecting = PNGSequenceDetector(),
        sequenceEncoderFactory: @escaping () -> any GifskiSequenceEncoding = { GifskiSequenceEncoder() },
        compressorFactory: @escaping CompressorFactory = { engine, mode in
            makeDefaultCompressor(for: engine, mode: mode)
        }
    ) {
        self.preferences = preferences
        self.settings = loadPersistedSettings ? Self.loadSettings(from: preferences) : settings
        self.tasks = tasks
        self.fileDiscovery = fileDiscovery
        self.sequenceDetector = sequenceDetector
        self.sequenceEncoderFactory = sequenceEncoderFactory
        self.compressorFactory = compressorFactory
        self.reservedOutputURLs = Set(tasks.compactMap(\.outputURL))
    }

    convenience init(
        settings: AppSettings = AppSettings(),
        tasks: [CompressionTask] = [],
        fileDiscovery: FileDiscovery = FileDiscovery(),
        preferences: UserDefaults = .standard,
        loadPersistedSettings: Bool = true,
        sequenceDetector: any PNGSequenceDetecting = PNGSequenceDetector(),
        sequenceEncoderFactory: @escaping () -> any GifskiSequenceEncoding = { GifskiSequenceEncoder() },
        compressorFactory: @escaping (CompressionEngine) -> any ImageCompressor
    ) {
        self.init(
            settings: settings,
            tasks: tasks,
            fileDiscovery: fileDiscovery,
            preferences: preferences,
            loadPersistedSettings: loadPersistedSettings,
            sequenceDetector: sequenceDetector,
            sequenceEncoderFactory: sequenceEncoderFactory,
            compressorFactory: { engine, _ in compressorFactory(engine) }
        )
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
        let previousDiscovery = importDiscoveryTail
        let fileDiscovery = fileDiscovery
        let sequenceDetector = sequenceDetector
        let importTask = Task { [weak self] in
            await previousDiscovery?.value
            let result = await Task.detached(priority: .utility) {
                let discovery = fileDiscovery.discover(urls: urls)
                let sequences = sequenceDetector.detect(in: discovery.images)
                let candidateURLs = Set(sequences.flatMap(\.frameURLs))
                let regularImages = discovery.images.filter { !candidateURLs.contains($0.fileURL) }
                return ImportDiscoveryResult(
                    resolution: ImportResolution(
                        regularImages: regularImages,
                        sequences: sequences
                    ),
                    skippedNonImageCount: discovery.skippedNonImageCount
                )
            }.value
            self?.receiveImportDiscovery(result)
        }
        importDiscoveryTail = importTask
    }

    func resolvePendingImport(convertSequence: Bool) {
        guard let resolution = activeImportResolution,
              case .convertSequences = pendingImportPrompt else {
            return
        }

        pendingImportPrompt = nil
        activeImportResolution = nil
        if convertSequence {
            updateGIFSettings { $0.isPNGSequenceConversionEnabled = true }
            prepareAndEnqueueConvertedSequences(resolution)
        } else {
            enqueueRegularImages(in: resolution, includingSequenceFrames: true)
        }
        processNextImportResolutionIfPossible()
    }

    func resolvePendingImport(compressInstead: Bool) {
        guard let resolution = activeImportResolution,
              case .compressWithoutSequence = pendingImportPrompt else {
            return
        }

        pendingImportPrompt = nil
        activeImportResolution = nil
        if compressInstead {
            updateGIFSettings { $0.isPNGSequenceConversionEnabled = false }
            enqueueRegularImages(in: resolution, includingSequenceFrames: false)
        } else {
            importNotice = ImportNotice(message: "当前文件夹没有 PNG 序列，无法转 GIF")
        }
        processNextImportResolutionIfPossible()
    }

    func dismissImportNotice() {
        importNotice = nil
        processNextImportResolutionIfPossible()
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

    private func receiveImportDiscovery(_ result: ImportDiscoveryResult) {
        skippedNonPNGCount += result.skippedNonImageCount
        guard !result.resolution.regularImages.isEmpty || !result.resolution.sequences.isEmpty else {
            return
        }
        pendingImportResolutions.append(result.resolution)
        processNextImportResolutionIfPossible()
    }

    private func processNextImportResolutionIfPossible() {
        guard activeImportResolution == nil,
              pendingImportPrompt == nil,
              !isPreparingSequenceImport,
              importNotice == nil else {
            return
        }

        while !pendingImportResolutions.isEmpty {
            let resolution = pendingImportResolutions.removeFirst()
            if !resolution.sequences.isEmpty {
                if settings.gif.isPNGSequenceConversionEnabled {
                    prepareAndEnqueueConvertedSequences(resolution)
                    return
                }
                activeImportResolution = resolution
                pendingImportPrompt = .convertSequences(resolution)
                return
            }

            if settings.gif.isPNGSequenceConversionEnabled {
                activeImportResolution = resolution
                pendingImportPrompt = .compressWithoutSequence(resolution)
                return
            }
            enqueueRegularImages(in: resolution, includingSequenceFrames: false)
        }
    }

    private func prepareAndEnqueueConvertedSequences(_ resolution: ImportResolution) {
        isPreparingSequenceImport = true
        let sequenceDetector = sequenceDetector
        Task { [weak self] in
            let preflightResults = await Task.detached(priority: .utility) {
                resolution.sequences.map { sequence in
                    SequencePreflightResult(
                        sequence: sequence,
                        dimensionsAreValid: (try? sequenceDetector.validateFrameDimensions(sequence)) != nil
                    )
                }
            }.value
            guard let self else { return }
            self.enqueueConvertedResolution(resolution, preflightResults: preflightResults)
            self.isPreparingSequenceImport = false
            self.processNextImportResolutionIfPossible()
        }
    }

    private func enqueueConvertedResolution(
        _ resolution: ImportResolution,
        preflightResults: [SequencePreflightResult]
    ) {
        var prepared: [CompressionQueue.WorkItem] = []
        var failed: [CompressionQueue.WorkItem] = []
        var outputPlanner = makeOutputPlanner()

        for result in preflightResults {
            appendSequenceWorkItem(
                for: result.sequence,
                dimensionsAreValid: result.dimensionsAreValid,
                prepared: &prepared,
                failed: &failed,
                outputPlanner: &outputPlanner
            )
        }
        appendFileWorkItems(
            for: resolution.regularImages,
            prepared: &prepared,
            failed: &failed,
            outputPlanner: &outputPlanner
        )
        finishEnqueue(prepared: prepared, failed: failed, outputPlanner: outputPlanner)
    }

    private func enqueueRegularImages(in resolution: ImportResolution, includingSequenceFrames: Bool) {
        var images = resolution.regularImages
        if includingSequenceFrames {
            images.append(contentsOf: resolution.sequences.flatMap { sequence in
                sequence.frameURLs.map {
                    DiscoveredImage(
                        fileURL: $0,
                        importedFolderRoot: sequence.importedFolderRoot,
                        format: .png
                    )
                }
            })
        }

        var prepared: [CompressionQueue.WorkItem] = []
        var failed: [CompressionQueue.WorkItem] = []
        var outputPlanner = makeOutputPlanner()
        appendFileWorkItems(
            for: images,
            prepared: &prepared,
            failed: &failed,
            outputPlanner: &outputPlanner
        )
        finishEnqueue(prepared: prepared, failed: failed, outputPlanner: outputPlanner)
    }

    private func makeOutputPlanner() -> OutputPlanner {
        OutputPlanner(
            policy: settings.outputPolicy,
            customDirectory: settings.customOutputDirectory,
            reservedFinalURLs: reservedOutputURLs
        )
    }

    private func appendSequenceWorkItem(
        for sequence: PNGSequence,
        dimensionsAreValid: Bool,
        prepared: inout [CompressionQueue.WorkItem],
        failed: inout [CompressionQueue.WorkItem],
        outputPlanner: inout OutputPlanner
    ) {
        guard let representativeSource = sequence.frameURLs.first else {
            return
        }

        guard dimensionsAreValid else {
            failed.append(CompressionQueue.WorkItem(
                task: failedSequenceTask(
                    sequence: sequence,
                    sourceURL: representativeSource,
                    failure: CompressionFailure(
                        code: .outputInvalid,
                        technicalMessage: "帧尺寸不一致，无法转 GIF"
                    )
                ),
                operation: .pngSequence(
                    sequenceEncoderFactory(),
                    quality: gifskiQuality(for: settings.mode),
                    frameRate: settings.gif.frameRate.value,
                    loop: settings.gif.loop
                )
            ))
            return
        }

        do {
            let output = try outputPlanner.prepareGeneratedGIF(
                representativeSource: representativeSource,
                outputFileName: sequence.outputFileName,
                importedFolderRoot: sequence.importedFolderRoot
            )
            let task = CompressionTask(
                sourceURL: representativeSource,
                sourceURLs: sequence.frameURLs,
                displayName: output.finalURL.lastPathComponent,
                inputKind: .pngSequence(frameCount: sequence.frameURLs.count),
                outputURL: output.finalURL,
                temporaryOutputURL: output.temporaryURL,
                allowsReplacingExistingOutput: output.allowsReplacingExistingFile,
                originalFileSize: totalFileSize(at: sequence.frameURLs),
                format: .gif,
                engine: .gifski,
                displayMode: settings.mode
            )
            prepared.append(CompressionQueue.WorkItem(
                task: task,
                operation: .pngSequence(
                    sequenceEncoderFactory(),
                    quality: gifskiQuality(for: settings.mode),
                    frameRate: settings.gif.frameRate.value,
                    loop: settings.gif.loop
                )
            ))
        } catch let error as OutputPolicyError {
            failed.append(CompressionQueue.WorkItem(
                task: failedSequenceTask(
                    sequence: sequence,
                    sourceURL: representativeSource,
                    failure: CompressionFailure(
                        code: .outputPolicyInvalid,
                        technicalMessage: error.localizedDescription
                    )
                ),
                operation: .pngSequence(
                    sequenceEncoderFactory(),
                    quality: gifskiQuality(for: settings.mode),
                    frameRate: settings.gif.frameRate.value,
                    loop: settings.gif.loop
                )
            ))
        } catch {
            failed.append(CompressionQueue.WorkItem(
                task: failedSequenceTask(
                    sequence: sequence,
                    sourceURL: representativeSource,
                    failure: CompressionFailure(
                        code: .outputPolicyInvalid,
                        technicalMessage: error.localizedDescription
                    )
                ),
                operation: .pngSequence(
                    sequenceEncoderFactory(),
                    quality: gifskiQuality(for: settings.mode),
                    frameRate: settings.gif.frameRate.value,
                    loop: settings.gif.loop
                )
            ))
        }
    }

    private func failedSequenceTask(
        sequence: PNGSequence,
        sourceURL: URL,
        failure: CompressionFailure
    ) -> CompressionTask {
        CompressionTask(
            sourceURL: sourceURL,
            sourceURLs: sequence.frameURLs,
            displayName: sequence.outputFileName,
            inputKind: .pngSequence(frameCount: sequence.frameURLs.count),
            isRetryable: false,
            originalFileSize: totalFileSize(at: sequence.frameURLs),
            state: .failed(failure),
            format: .gif,
            engine: .gifski,
            displayMode: settings.mode
        )
    }

    private func appendFileWorkItems(
        for images: [DiscoveredImage],
        prepared: inout [CompressionQueue.WorkItem],
        failed: inout [CompressionQueue.WorkItem],
        outputPlanner: inout OutputPlanner
    ) {
        for image in images {
            let sourceURL = image.fileURL
            guard let configuration = compressionConfiguration(for: image.format) else {
                continue
            }
            let compressor = compressorFactory(configuration.engine, configuration.displayMode)
            do {
                let output = try outputPlanner.prepare(
                    source: sourceURL,
                    importedFolderRoot: image.importedFolderRoot
                )
                prepared.append(
                    CompressionQueue.WorkItem(task: CompressionTask(
                        sourceURL: sourceURL,
                        outputURL: output.finalURL,
                        temporaryOutputURL: output.temporaryURL,
                        allowsReplacingExistingOutput: output.allowsReplacingExistingFile,
                        originalFileSize: fileSize(at: sourceURL),
                        format: image.format,
                        engine: configuration.engine,
                        displayMode: configuration.displayMode
                    ), compressor: compressor)
                )
            } catch let error as OutputPolicyError {
                failed.append(
                    CompressionQueue.WorkItem(task: CompressionTask(
                        sourceURL: sourceURL,
                        state: .failed(CompressionFailure(
                            code: .outputPolicyInvalid,
                            technicalMessage: error.localizedDescription
                        )),
                        format: image.format,
                        engine: configuration.engine,
                        displayMode: configuration.displayMode
                    ), compressor: compressor)
                )
            } catch {
                failed.append(
                    CompressionQueue.WorkItem(task: CompressionTask(
                        sourceURL: sourceURL,
                        state: .failed(CompressionFailure(
                            code: .outputPolicyInvalid,
                            technicalMessage: error.localizedDescription
                        )),
                        format: image.format,
                        engine: configuration.engine,
                        displayMode: configuration.displayMode
                    ), compressor: compressor)
                )
            }
        }
    }

    private func finishEnqueue(
        prepared: [CompressionQueue.WorkItem],
        failed: [CompressionQueue.WorkItem],
        outputPlanner: OutputPlanner
    ) {
        reservedOutputURLs = outputPlanner.plannedFinalURLs
        startQueue(with: prepared, failed: failed)
    }

    private func startQueue(with preparedTasks: [CompressionQueue.WorkItem], failed failedTasks: [CompressionQueue.WorkItem]) {
        guard !preparedTasks.isEmpty || !failedTasks.isEmpty else {
            return
        }
        let queue = existingOrNewQueue(defaultCompressor: UnconfiguredCompressor(engine: .oxipng))

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

    private func compressionConfiguration(for format: ImageFormat) -> (engine: CompressionEngine, displayMode: CompressionMode)? {
        switch format {
        case .png:
            switch settings.mode {
            case .lossless: return (.oxipng, .lossless)
            case .balanced: return (.pngquant, .balanced)
            }
        case .jpeg:
            return (.mozjpeg, .balanced)
        case .gif:
            return (.gifsicle, settings.mode)
        }
    }

    private func gifskiQuality(for mode: CompressionMode) -> Int {
        switch mode {
        case .lossless: 100
        case .balanced: 80
        }
    }

    private func totalFileSize(at urls: [URL]) -> Int64? {
        var total: Int64 = 0
        for url in urls {
            guard let size = fileSize(at: url) else {
                return nil
            }
            total += size
        }
        return total
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(value)
    }

    private func updateGIFSettings(_ update: (inout GIFSettings) -> Void) {
        var updatedSettings = settings
        update(&updatedSettings.gif)
        settings = updatedSettings
    }

    private func persist(_ settings: AppSettings) {
        preferences.set(settings.outputPolicy.persistenceValue, forKey: PreferenceKey.outputPolicy)
        preferences.set(settings.mode.rawValue, forKey: PreferenceKey.compressionMode)
        preferences.set(settings.customOutputDirectory?.path, forKey: PreferenceKey.customOutputDirectory)
        preferences.set(settings.gif.isPNGSequenceConversionEnabled, forKey: PreferenceKey.gifSequenceEnabled)
        preferences.set(settings.gif.frameRate.value, forKey: PreferenceKey.gifFrameRate)
        preferences.set(settings.gif.frameRate.persistenceKind, forKey: PreferenceKey.gifFrameRateKind)
        preferences.set(settings.gif.loop.rawValue, forKey: PreferenceKey.gifLoop)
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
            customOutputDirectory: storedDirectory,
            gif: gifSettings(from: preferences)
        )
    }

    private static func gifSettings(from preferences: UserDefaults) -> GIFSettings {
        let defaults = GIFSettings()
        let isEnabled = preferences.object(forKey: PreferenceKey.gifSequenceEnabled) as? Bool
            ?? defaults.isPNGSequenceConversionEnabled
        let storedFrameRate = preferences.object(forKey: PreferenceKey.gifFrameRate) as? Int
        let frameRate: GIFFrameRate
        switch preferences.string(forKey: PreferenceKey.gifFrameRateKind) {
        case "preset" where GIFFrameRate.presetValues.contains(storedFrameRate ?? -1):
            frameRate = .preset(storedFrameRate!)
        case "custom" where storedFrameRate.flatMap(GIFFrameRate.custom(validating:)) != nil:
            frameRate = GIFFrameRate.custom(validating: storedFrameRate!)!
        default:
            frameRate = defaults.frameRate
        }
        let loop = preferences.string(forKey: PreferenceKey.gifLoop)
            .flatMap(GIFLoop.init(rawValue:))
            ?? defaults.loop
        return GIFSettings(
            isPNGSequenceConversionEnabled: isEnabled,
            frameRate: frameRate,
            loop: loop
        )
    }
}

private enum PreferenceKey {
    static let outputPolicy = "pngcut.output-policy"
    static let compressionMode = "pngcut.compression-mode"
    static let customOutputDirectory = "pngcut.custom-output-directory"
    static let gifSequenceEnabled = "pngcut.gif.sequence-enabled"
    static let gifFrameRate = "pngcut.gif.frame-rate"
    static let gifFrameRateKind = "pngcut.gif.frame-rate-kind"
    static let gifLoop = "pngcut.gif.loop"
}

private extension GIFFrameRate {
    var persistenceKind: String {
        switch self {
        case .preset: "preset"
        case .custom: "custom"
        }
    }
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
