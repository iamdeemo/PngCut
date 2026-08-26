import AppKit
import XCTest
@testable import PngCut

@MainActor
final class PngCutTests: XCTestCase {
    func testDefaultsUseLosslessAndEmptyQueue() {
        let model = AppModel.preview()
        XCTAssertEqual(model.settings.mode, .lossless)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testExplicitlySelectedCompressionModeIsRestoredOnRelaunch() {
        let suiteName = "com.pngcut.app.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set("balanced", forKey: "pngcut.compression-mode")

        let model = AppModel(preferences: preferences)

        XCTAssertEqual(model.settings.mode, .balanced)
    }

    func testAppUsesSimplifiedChineseAsItsDevelopmentLocalization() {
        XCTAssertEqual(Bundle(for: AppModel.self).developmentLocalization, "zh-Hans")
    }

    func testWorkspacePaletteUsesRequestedF4Gray() {
        let color = AppPalette.workspace

        XCTAssertEqual(color.redComponent, 244 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.greenComponent, 244 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blueComponent, 244 / 255, accuracy: 0.0001)
    }

    func testDrawerPaletteUsesRequestedFCFCFC() {
        let color = AppPalette.drawer

        XCTAssertEqual(color.redComponent, 252 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.greenComponent, 252 / 255, accuracy: 0.0001)
        XCTAssertEqual(color.blueComponent, 252 / 255, accuracy: 0.0001)
    }

    func testAddingFilesDuringAnActiveQueueKeepsBothTasksAndTheirResultsInOrder() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelQueueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = directory.appendingPathComponent("first.png")
        let second = directory.appendingPathComponent("second.png")
        try Data("first source".utf8).write(to: first)
        try Data("second source".utf8).write(to: second)
        let compressor = BlockingModelCompressor()
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            loadPersistedSettings: false,
            compressorFactory: { _ in compressor }
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("first_pngcut.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("second_pngcut.png").path))
    }

    func testAdjacentFolderImportCreatesSiblingPngcutFolderAndPreservesRelativeFilenames() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelFolderOutputTests-\(UUID().uuidString)", isDirectory: true)
        let sourceFolder = directory.appendingPathComponent("project.assets", isDirectory: true)
        let nestedFolder = sourceFolder.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = sourceFolder.appendingPathComponent("banner.png")
        let second = nestedFolder.appendingPathComponent("photo.JPG")
        try Data("first source".utf8).write(to: first)
        try Data("second source".utf8).write(to: second)

        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            loadPersistedSettings: false,
            compressorFactory: { _ in ParentDirectoryAgnosticCompressor() }
        )

        model.add(urls: [sourceFolder])
        await waitUntil {
            model.tasks.count == 2 && model.tasks.allSatisfy { $0.state == .completed }
        }

        let outputFolder = directory.appendingPathComponent("project.assets_pngcut", isDirectory: true)
        XCTAssertEqual(
            Set(model.tasks.compactMap(\.outputURL)),
            Set([
                outputFolder.appendingPathComponent("banner.png"),
                outputFolder.appendingPathComponent("nested/photo.JPG")
            ])
        )
        XCTAssertEqual(try Data(contentsOf: outputFolder.appendingPathComponent("banner.png")), Data("optimized".utf8))
        XCTAssertEqual(try Data(contentsOf: outputFolder.appendingPathComponent("nested/photo.JPG")), Data("optimized".utf8))
    }

    func testAddingNonPNGFilesPublishesTheirSkippedCount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nonPNG = directory.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: nonPNG)
        let model = AppModel(fileDiscovery: FileDiscovery(), loadPersistedSettings: false)

        model.add(urls: [nonPNG])

        XCTAssertEqual(model.skippedNonPNGCount, 1)
        XCTAssertTrue(model.tasks.isEmpty)
    }

    func testPreparingSameNameFilesForCustomOutputKeepsDistinctDestinations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelOutputTests-\(UUID().uuidString)", isDirectory: true)
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
            loadPersistedSettings: false,
            compressorFactory: { _ in compressor }
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
                outputDirectory.appendingPathComponent("icon_pngcut.png"),
                outputDirectory.appendingPathComponent("icon_pngcut-2.png")
            ]
        )
        XCTAssertEqual(try Data(contentsOf: first), Data("first source".utf8))
        XCTAssertEqual(try Data(contentsOf: second), Data("second source".utf8))
    }

    func testOverwriteNoChangeKeepsTheOriginalFileEntityAndMetadata() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelOverwriteNoChangeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        try Data("original source".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let compressor = NoChangeModelCompressor()
        let model = AppModel(
            settings: AppSettings(mode: .balanced, outputPolicy: .overwrite),
            loadPersistedSettings: false,
            compressorFactory: { _ in compressor }
        )

        model.add(urls: [source])
        await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

        let afterAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual(model.tasks[0].outputURL, source.standardizedFileURL)
        XCTAssertNil(model.tasks[0].temporaryOutputURL)
        XCTAssertEqual(try Data(contentsOf: source), Data("original source".utf8))
        XCTAssertEqual(afterAttributes[.systemFileNumber] as? NSNumber, beforeAttributes[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(afterAttributes[.modificationDate] as? Date, beforeAttributes[.modificationDate] as? Date)
        XCTAssertEqual(afterAttributes[.posixPermissions] as? NSNumber, beforeAttributes[.posixPermissions] as? NSNumber)
    }

    func testBalancedPNGUsesPngquant() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelBalancedPNGTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        try Data("source".utf8).write(to: source)
        let factory = RecordingCompressorFactory()
        let model = AppModel(
            settings: AppSettings(mode: .balanced),
            fileDiscovery: FileDiscovery(),
            loadPersistedSettings: false,
            compressorFactory: { engine in factory.compressor(for: engine) }
        )

        model.add(urls: [source])
        await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

        XCTAssertEqual(factory.requestedEngines, [.pngquant])
        XCTAssertEqual(model.tasks[0].engine, .pngquant)
        XCTAssertEqual(model.tasks[0].displayMode, .balanced)
    }

    func testJPEGUsesMozjpegAndBalancedDisplayModeWhenPNGPreferenceIsLossless() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelJPEGTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.jpg")
        try Data("source".utf8).write(to: source)
        let factory = RecordingCompressorFactory()
        let model = AppModel(
            settings: AppSettings(mode: .lossless),
            fileDiscovery: FileDiscovery(),
            loadPersistedSettings: false,
            compressorFactory: { engine in factory.compressor(for: engine) }
        )

        model.add(urls: [source])
        await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

        XCTAssertEqual(factory.requestedEngines, [.mozjpeg])
        XCTAssertEqual(model.tasks[0].format, .jpeg)
        XCTAssertEqual(model.tasks[0].engine, .mozjpeg)
        XCTAssertEqual(model.tasks[0].displayMode, .balanced)
    }

    func testRetryRetainsTheFailedTasksRecordedEngine() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelRetryEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        try Data("source".utf8).write(to: source)
        let factory = RecordingCompressorFactory(failFirstEngine: .pngquant)
        let model = AppModel(
            settings: AppSettings(mode: .balanced),
            fileDiscovery: FileDiscovery(),
            loadPersistedSettings: false,
            compressorFactory: { engine in factory.compressor(for: engine) }
        )

        model.add(urls: [source])
        await waitUntil { model.tasks.count == 1 && model.tasks[0].state.isFailed }
        model.retryFailed()
        await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

        let recordedEngines = await factory.recordedEngines()
        XCTAssertEqual(factory.requestedEngines, [.pngquant])
        XCTAssertEqual(recordedEngines, [.pngquant, .pngquant])
        XCTAssertEqual(model.tasks[0].engine, .pngquant)
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
    ) async throws -> CompressionOutcome {
        startedCount += 1
        progress(0.5)
        if startedCount == 1 {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }
        try Data("optimized".utf8).write(to: temporaryDestination)
        return .compressed
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

@MainActor
private final class RecordingCompressorFactory {
    private let failFirstEngine: CompressionEngine?
    private var compressors: [CompressionEngine: RecordingModelCompressor] = [:]
    private(set) var requestedEngines: [CompressionEngine] = []

    init(failFirstEngine: CompressionEngine? = nil) {
        self.failFirstEngine = failFirstEngine
    }

    func compressor(for engine: CompressionEngine) -> any ImageCompressor {
        requestedEngines.append(engine)
        if let compressor = compressors[engine] {
            return compressor
        }
        let compressor = RecordingModelCompressor(engine: engine, failsFirstCompression: engine == failFirstEngine)
        compressors[engine] = compressor
        return compressor
    }

    func recordedEngines() async -> [CompressionEngine] {
        var result: [CompressionEngine] = []
        for engine in requestedEngines {
            guard let compressor = compressors[engine] else { continue }
            result.append(contentsOf: await compressor.recordedEngines())
        }
        return result
    }
}

private actor RecordingModelCompressor: ImageCompressor {
    private let engine: CompressionEngine
    private var failsFirstCompression: Bool
    private var engines: [CompressionEngine] = []

    init(engine: CompressionEngine, failsFirstCompression: Bool) {
        self.engine = engine
        self.failsFirstCompression = failsFirstCompression
    }

    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        engines.append(engine)
        if failsFirstCompression {
            failsFirstCompression = false
            throw CompressionFailure.localExecution("expected failure")
        }
        try FileManager.default.createDirectory(at: temporaryDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("optimized".utf8).write(to: temporaryDestination)
        progress(1)
        return .compressed
    }

    func recordedEngines() -> [CompressionEngine] {
        engines
    }
}

private struct NoChangeModelCompressor: ImageCompressor {
    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        progress(1)
        return .noChange
    }
}

private struct ParentDirectoryAgnosticCompressor: ImageCompressor {
    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        try Data("optimized".utf8).write(to: temporaryDestination)
        progress(1)
        return .compressed
    }
}
