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

private func makeDefaultCompressor(
    mode: CompressionMode,
    apiKey: String
) -> any ImageCompressor {
    switch mode {
    case .lossless:
        OxipngCompressor()
    case .balanced:
        TinifyCompressor(apiKey: apiKey)
    }
}

private func validateTinifyAPIKey(_ apiKey: String) async throws {
    try await TinifyCompressor(apiKey: apiKey).validateAPIKey()
}

@MainActor
final class AppModel: ObservableObject {
    private static let apiKeyPreferenceKey = "tinify-api-key"
    private static let validatedAPIKeyPreferenceKey = "validated-tinify-api-key"
    private static let legacyTestFixtureAPIKey = "trimmed-key"

    @Published var settings: AppSettings {
        didSet { persist(settings) }
    }
    @Published private(set) var tasks: [CompressionTask]
    @Published private(set) var skippedNonPNGCount = 0
    @Published var apiKey = "" {
        didSet {
            preferences.set(apiKey, forKey: Self.apiKeyPreferenceKey)
            guard apiKey != validatedAPIKey else { return }
            validatedAPIKey = ""
            preferences.removeObject(forKey: Self.validatedAPIKeyPreferenceKey)
            validationGeneration += 1
            isTinifyValidated = false
        }
    }
    @Published private(set) var isTinifyValidated: Bool
    @Published private(set) var validationMessage: String?

    private let fileDiscovery: FileDiscovery
    private let preferences: UserDefaults
    private let compressorFactory: (CompressionMode, String) -> any ImageCompressor
    private let apiKeyValidator: (String) async throws -> Void
    private var queue: CompressionQueue?
    private var enqueueTail: Task<Void, Never>?
    private var reservedOutputURLs: Set<URL>
    private var validationGeneration = 0
    private var validatedAPIKey = ""

    init(
        settings: AppSettings = AppSettings(),
        tasks: [CompressionTask] = [],
        fileDiscovery: FileDiscovery = FileDiscovery(),
        keychain _: KeychainStore = KeychainStore(),
        isTinifyValidated: Bool? = nil,
        preferences: UserDefaults = .standard,
        loadPersistedSettings: Bool = true,
        compressorFactory: @escaping (CompressionMode, String) -> any ImageCompressor = makeDefaultCompressor,
        apiKeyValidator: @escaping (String) async throws -> Void = validateTinifyAPIKey
    ) {
        self.preferences = preferences
        self.settings = loadPersistedSettings ? Self.loadSettings(from: preferences) : settings
        self.tasks = tasks
        self.fileDiscovery = fileDiscovery
        self.compressorFactory = compressorFactory
        self.apiKeyValidator = apiKeyValidator
        self.reservedOutputURLs = Set(tasks.compactMap(\.outputURL))

        var storedKey = preferences.string(forKey: Self.apiKeyPreferenceKey) ?? ""
        var storedValidatedKey = preferences.string(forKey: Self.validatedAPIKeyPreferenceKey) ?? ""
        if storedKey == Self.legacyTestFixtureAPIKey {
            preferences.removeObject(forKey: Self.apiKeyPreferenceKey)
            preferences.removeObject(forKey: Self.validatedAPIKeyPreferenceKey)
            storedKey = ""
            storedValidatedKey = ""
        }
        let hasMatchingValidatedKey = !storedKey.isEmpty && storedKey == storedValidatedKey
        apiKey = storedKey
        validatedAPIKey = hasMatchingValidatedKey ? storedValidatedKey : ""
        if !hasMatchingValidatedKey {
            preferences.removeObject(forKey: Self.validatedAPIKeyPreferenceKey)
        }
        self.isTinifyValidated = hasMatchingValidatedKey && (isTinifyValidated ?? true)
        self.validationMessage = self.isTinifyValidated ? "已验证" : nil
        if !preferences.bool(forKey: PreferenceKey.hasExplicitCompressionModeSelection) {
            self.settings.mode = .lossless
            preferences.set(CompressionMode.lossless.rawValue, forKey: PreferenceKey.compressionMode)
        }
    }

    static func preview() -> AppModel {
        AppModel(isTinifyValidated: false, loadPersistedSettings: false)
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
        let discovered = discovery.files
        guard !discovered.isEmpty else { return }

        var prepared: [CompressionTask] = []
        for sourceURL in discovered {
            do {
                let output = try settings.outputPolicy.prepare(
                    source: sourceURL,
                    customDirectory: settings.customOutputDirectory,
                    reservedFinalURLs: reservedOutputURLs
                )
                reservedOutputURLs.insert(output.finalURL)
                prepared.append(
                    CompressionTask(
                        sourceURL: sourceURL,
                        outputURL: output.finalURL,
                        temporaryOutputURL: output.temporaryURL,
                        allowsReplacingExistingOutput: output.allowsReplacingExistingFile,
                        originalFileSize: fileSize(at: sourceURL)
                    )
                )
            } catch {
                prepared.append(
                    CompressionTask(
                        sourceURL: sourceURL,
                        state: .failed(.outputValidation(error.localizedDescription))
                    )
                )
            }
        }

        startQueue(with: prepared)
    }

    func retryFailed() {
        Task { [weak self] in
            guard let self, let queue else { return }
            let balancedCompressor: (any ImageCompressor)?
            if self.isTinifyValidated, !self.apiKey.isEmpty {
                balancedCompressor = self.compressorFactory(.balanced, self.apiKey)
            } else {
                balancedCompressor = nil
            }
            await queue.retryFailed(replacingInvalidAPIKeyCompressorWith: balancedCompressor)
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

    func validateTinifyKey() {
        let candidate = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKey = candidate
        validationGeneration += 1
        let generation = validationGeneration
        guard !candidate.isEmpty else {
            isTinifyValidated = false
            validationMessage = "请输入 API Key"
            return
        }

        validationMessage = "正在验证…"
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.apiKeyValidator(candidate)
                guard self.validationGeneration == generation, self.apiKey == candidate else { return }
                validatedAPIKey = candidate
                preferences.set(candidate, forKey: Self.validatedAPIKeyPreferenceKey)
                apiKey = candidate
                isTinifyValidated = true
                validationMessage = "已验证"
            } catch let failure as CompressionFailure {
                guard self.validationGeneration == generation, self.apiKey == candidate else { return }
                isTinifyValidated = false
                validationMessage = Self.message(for: failure)
            } catch {
                guard self.validationGeneration == generation, self.apiKey == candidate else { return }
                isTinifyValidated = false
                validationMessage = "验证失败，请稍后重试"
            }
        }
    }

    func setCompressionMode(_ mode: CompressionMode) {
        preferences.set(true, forKey: PreferenceKey.hasExplicitCompressionModeSelection)
        settings.mode = mode
    }

    private func startQueue(with preparedTasks: [CompressionTask]) {
        let compressor: any ImageCompressor
        switch settings.mode {
        case .lossless:
            compressor = compressorFactory(.lossless, apiKey)
        case .balanced:
            guard isTinifyValidated, !apiKey.isEmpty else {
                let invalidTasks = preparedTasks.map { task in
                    var task = task
                    task.state = .failed(.invalidAPIKey)
                    return task
                }
                let queue = existingOrNewQueue(defaultCompressor: compressorFactory(.balanced, apiKey))
                Task {
                    await queue.recordFailed(invalidTasks, using: compressorFactory(.balanced, apiKey))
                }
                return
            }
            compressor = compressorFactory(.balanced, apiKey)
        }

        let queue = existingOrNewQueue(defaultCompressor: compressor)

        let previousEnqueue = enqueueTail
        let enqueue = Task {
            await previousEnqueue?.value
            await queue.enqueue(preparedTasks, using: compressor)
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

    private static func message(for failure: CompressionFailure) -> String {
        switch failure {
        case .invalidAPIKey: "API Key 无效"
        case .quotaExceeded: "本月额度已用完"
        case .transport: "网络连接失败"
        case .apiResponse: "Tinify 暂时无法处理请求"
        case .localExecution, .outputValidation: "验证失败，请稍后重试"
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
    static let outputPolicy = "ffpng.output-policy"
    static let compressionMode = "ffpng.compression-mode"
    static let hasExplicitCompressionModeSelection = "ffpng.has-explicit-compression-mode-selection"
    static let customOutputDirectory = "ffpng.custom-output-directory"
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
