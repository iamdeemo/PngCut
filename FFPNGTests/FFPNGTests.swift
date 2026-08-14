import XCTest
@testable import FFPNG

@MainActor
final class FFPNGTests: XCTestCase {
    func testDefaultsUseLosslessAndEmptyQueue() {
        let model = AppModel.preview()
        XCTAssertEqual(model.settings.mode, .lossless)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testPersistedValidatedKeyKeepsLosslessAsTheLaunchDefault() {
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("cached-key", forKey: "tinify-api-key")
        preferences.set("cached-key", forKey: "validated-tinify-api-key")

        let model = AppModel(
            settings: AppSettings(mode: .balanced),
            preferences: preferences,
            loadPersistedSettings: false
        )

        XCTAssertEqual(model.apiKey, "cached-key")
        XCTAssertTrue(model.isTinifyValidated)
        XCTAssertEqual(model.settings.mode, .lossless)
    }

    func testOrphanedValidationMarkerIsClearedWhenNoAPIKeyIsStored() {
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("previously-validated-key", forKey: "validated-tinify-api-key")

        let model = AppModel(preferences: preferences)

        XCTAssertEqual(model.apiKey, "")
        XCTAssertFalse(model.isTinifyValidated)
        XCTAssertNil(preferences.string(forKey: "validated-tinify-api-key"))
    }

    func testLegacyTestFixtureKeyIsRemovedInsteadOfBeingRestoredAsValidated() {
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("trimmed-key", forKey: "tinify-api-key")
        preferences.set("trimmed-key", forKey: "validated-tinify-api-key")

        let model = AppModel(preferences: preferences)

        XCTAssertEqual(model.apiKey, "")
        XCTAssertFalse(model.isTinifyValidated)
        XCTAssertNil(preferences.string(forKey: "tinify-api-key"))
        XCTAssertNil(preferences.string(forKey: "validated-tinify-api-key"))
    }

    func testExplicitlySelectedCompressionModeIsRestoredOnRelaunch() {
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("balanced", forKey: "ffpng.compression-mode")
        preferences.set(true, forKey: "ffpng.has-explicit-compression-mode-selection")

        let model = AppModel(preferences: preferences)

        XCTAssertEqual(model.settings.mode, .balanced)
    }

    func testAppUsesSimplifiedChineseAsItsDevelopmentLocalization() {
        XCTAssertEqual(Bundle(for: AppModel.self).developmentLocalization, "zh-Hans")
    }

    func testAddingFilesDuringAnActiveQueueKeepsBothTasksAndTheirResultsInOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFPNG-AppModelQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        try Data("first source".utf8).write(to: first)
        try Data("second source".utf8).write(to: second)
        let compressor = BlockingModelCompressor()
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            keychain: KeychainStore(),
            isTinifyValidated: false,
            loadPersistedSettings: false,
            compressorFactory: { _, _ in compressor }
        )

        model.add(urls: [first])
        await compressor.waitUntilStarted(count: 1)
        model.add(urls: [second])

        await compressor.releaseFirstCompression()
        await waitUntil {
            model.tasks.count == 2 && model.tasks.allSatisfy { $0.state == .completed }
        }

        XCTAssertEqual(model.tasks.map(\.sourceURL), [first.standardizedFileURL, second.standardizedFileURL])
        XCTAssertEqual(model.tasks.map(\.state), [.completed, .completed])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("first-optimized.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("second-optimized.png").path))
    }

    func testAddingNonPNGFilesPublishesTheirSkippedCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFPNG-AppModelDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nonPNG = directory.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: nonPNG)
        let model = AppModel(fileDiscovery: FileDiscovery(), keychain: KeychainStore(), loadPersistedSettings: false)

        model.add(urls: [nonPNG])

        XCTAssertEqual(model.skippedNonPNGCount, 1)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testPreparingSameNameFilesForCustomOutputKeepsDistinctDestinations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFPNG-AppModelOutputTests-\(UUID().uuidString)", isDirectory: true)
        let firstDirectory = directory.appendingPathComponent("a", isDirectory: true)
        let secondDirectory = directory.appendingPathComponent("b", isDirectory: true)
        let outputDirectory = directory.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = firstDirectory.appendingPathComponent("icon.png")
        let second = secondDirectory.appendingPathComponent("icon.png")
        try Data("first source".utf8).write(to: first)
        try Data("second source".utf8).write(to: second)
        let compressor = BlockingModelCompressor()
        let model = AppModel(
            settings: AppSettings(outputPolicy: .customDirectory, customOutputDirectory: outputDirectory),
            fileDiscovery: FileDiscovery(),
            keychain: KeychainStore(),
            loadPersistedSettings: false,
            compressorFactory: { _, _ in compressor }
        )

        model.add(urls: [first, second])
        await compressor.waitUntilStarted(count: 1)
        await compressor.releaseFirstCompression()
        await waitUntil {
            model.tasks.count == 2 && model.tasks.allSatisfy { $0.state == .completed }
        }

        XCTAssertEqual(
            model.tasks.compactMap(\.outputURL),
            [
                outputDirectory.appendingPathComponent("icon-optimized.png"),
                outputDirectory.appendingPathComponent("icon-optimized-2.png")
            ]
        )
        XCTAssertEqual(try Data(contentsOf: first), Data("first source".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second source".utf8))
    }

    func testInvalidBalancedTaskAddedDuringActiveQueueRemainsVisibleAfterPublish() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFPNG-AppModelInvalidBalancedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        try Data("first source".utf8).write(to: first)
        try Data("second source".utf8).write(to: second)
        let compressor = BlockingModelCompressor()
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            keychain: KeychainStore(),
            isTinifyValidated: false,
            loadPersistedSettings: false,
            compressorFactory: { _, _ in compressor }
        )

        model.add(urls: [first])
        await compressor.waitUntilStarted(count: 1)
        model.settings.mode = .balanced
        model.add(urls: [second])
        await compressor.releaseFirstCompression()
        await waitUntil { model.tasks.count == 2 && model.tasks[0].state == .completed }

        XCTAssertEqual(model.tasks.map(\.sourceURL), [first.standardizedFileURL, second.standardizedFileURL])
        XCTAssertEqual(model.tasks[1].state, .failed(.invalidAPIKey))
    }

    func testOlderTinifyValidationCannotOverwriteNewerKeyResult() async throws {
        let validator = ControlledKeyValidator()
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            keychain: KeychainStore(),
            preferences: preferences,
            loadPersistedSettings: false,
            apiKeyValidator: { key in try await validator.validate(key) }
        )

        model.apiKey = "old-key"
        model.validateTinifyKey()
        await validator.waitUntilOldKeyStarts()
        model.apiKey = "new-key"
        model.validateTinifyKey()
        await waitUntil { model.isTinifyValidated && model.apiKey == "new-key" }
        await validator.releaseOldKey()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(model.apiKey, "new-key")
        XCTAssertTrue(model.isTinifyValidated)
    }

    func testClearingKeyWhileValidationIsPendingPreventsStaleValidationFromRestoringIt() async throws {
        let validator = ControlledKeyValidator()
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            keychain: KeychainStore(),
            preferences: preferences,
            loadPersistedSettings: false,
            apiKeyValidator: { key in try await validator.validate(key) }
        )

        model.apiKey = "old-key"
        model.validateTinifyKey()
        await validator.waitUntilOldKeyStarts()
        model.apiKey = ""
        model.validateTinifyKey()
        await validator.releaseOldKey()
        await waitUntil { model.validationMessage == "已验证" }

        XCTAssertEqual(model.apiKey, "")
        XCTAssertFalse(model.isTinifyValidated)
    }

    func testEditingVerifiedKeyInvalidatesBalancedModeUntilTheReplacementIsValidated() {
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("original-key", forKey: "tinify-api-key")
        preferences.set("original-key", forKey: "validated-tinify-api-key")
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            keychain: KeychainStore(),
            isTinifyValidated: true,
            preferences: preferences,
            loadPersistedSettings: false
        )

        model.apiKey = "replacement-key"

        XCTAssertFalse(model.isTinifyValidated)
    }

    func testWhitespaceAroundKeyDoesNotDiscardSuccessfulValidation() async throws {
        let suiteName = "com.ffpng.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            keychain: KeychainStore(),
            preferences: preferences,
            loadPersistedSettings: false,
            apiKeyValidator: { key in XCTAssertEqual(key, "trimmed-key") }
        )

        model.apiKey = "  trimmed-key  "
        model.validateTinifyKey()
        await waitUntil { model.isTinifyValidated }

        XCTAssertEqual(model.apiKey, "trimmed-key")
        XCTAssertEqual(model.validationMessage, "已验证")
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
    }
}

private actor BlockingModelCompressor: ImageCompressor {
    private var startedCount = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?

    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        startedCount += 1
        progress(0.5)
        if startedCount == 1 {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        try Data("optimized".utf8).write(to: temporaryDestination)
    }

    func waitUntilStarted(count: Int) async {
        while startedCount < count {
            await Task.yield()
        }
    }

    func releaseFirstCompression() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

private actor ControlledKeyValidator {
    private var oldKeyContinuation: CheckedContinuation<Void, Never>?
    private var oldKeyStarted = false

    func validate(_ key: String) async throws {
        guard key == "old-key" else { return }
        oldKeyStarted = true
        await withCheckedContinuation { continuation in
            oldKeyContinuation = continuation
        }
    }

    func waitUntilOldKeyStarts() async {
        while !oldKeyStarted {
            await Task.yield()
        }
    }

    func releaseOldKey() {
        oldKeyContinuation?.resume()
        oldKeyContinuation = nil
    }
}
