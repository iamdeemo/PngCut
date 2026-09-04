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

    func testAddingNonPNGFilesPublishesTheirSkippedCount() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nonPNG = directory.appendingPathComponent("notes.txt")
        try Data("not an image".utf8).write(to: nonPNG)
        let model = AppModel(fileDiscovery: FileDiscovery(), loadPersistedSettings: false)

        model.add(urls: [nonPNG])
        let published = await waitUntil { model.skippedNonPNGCount == 1 }

        XCTAssertTrue(published)
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

    func testAddingGIFRoutesThroughGifsicle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-AppModelGIFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("animation.gif")
        try Data("GIF89a".utf8).write(to: source)
        let factory = RecordingCompressorFactory()
        let model = AppModel(
            fileDiscovery: FileDiscovery(),
            loadPersistedSettings: false,
            compressorFactory: { engine in factory.compressor(for: engine) }
        )

        model.add(urls: [source])
        await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

        XCTAssertEqual(factory.requestedEngines, [.gifsicle])
        XCTAssertEqual(model.tasks[0].engine, .gifsicle)
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
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
final class GIFImportAppModelTests: XCTestCase {
    func testGIFSettingsAreRestoredAndInvalidStoredValuesUseDefaults() {
        let suiteName = "com.pngcut.gif-settings.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        preferences.set(true, forKey: "pngcut.gif.sequence-enabled")
        preferences.set(17, forKey: "pngcut.gif.frame-rate")
        preferences.set("custom", forKey: "pngcut.gif.frame-rate-kind")
        preferences.set("once", forKey: "pngcut.gif.loop")

        let restored = AppModel(preferences: preferences)

        XCTAssertEqual(restored.settings.gif, GIFSettings(
            isPNGSequenceConversionEnabled: true,
            frameRate: .custom(17),
            loop: .once
        ))

        preferences.set(99, forKey: "pngcut.gif.frame-rate")
        preferences.set("unexpected", forKey: "pngcut.gif.frame-rate-kind")
        preferences.set("unexpected", forKey: "pngcut.gif.loop")

        let invalid = AppModel(preferences: preferences)

        XCTAssertEqual(invalid.settings.gif, GIFSettings(
            isPNGSequenceConversionEnabled: true,
            frameRate: .preset(30),
            loop: .forever
        ))
    }

    func testGIFSettingsRoundTripPersistsPresetAndCustomFrameRateKinds() {
        let suiteName = "com.pngcut.gif-settings-round-trip.tests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: preferences, loadPersistedSettings: false)

        model.settings = AppSettings(gif: GIFSettings(
            isPNGSequenceConversionEnabled: true,
            frameRate: .preset(25),
            loop: .once
        ))

        XCTAssertEqual(preferences.object(forKey: "pngcut.gif.sequence-enabled") as? Bool, true)
        XCTAssertEqual(preferences.object(forKey: "pngcut.gif.frame-rate") as? Int, 25)
        XCTAssertEqual(preferences.string(forKey: "pngcut.gif.frame-rate-kind"), "preset")
        XCTAssertEqual(preferences.string(forKey: "pngcut.gif.loop"), "once")
        XCTAssertEqual(AppModel(preferences: preferences).settings.gif, GIFSettings(
            isPNGSequenceConversionEnabled: true,
            frameRate: .preset(25),
            loop: .once
        ))

        model.settings = AppSettings(gif: GIFSettings(
            isPNGSequenceConversionEnabled: false,
            frameRate: .custom(17),
            loop: .forever
        ))

        XCTAssertEqual(preferences.object(forKey: "pngcut.gif.sequence-enabled") as? Bool, false)
        XCTAssertEqual(preferences.object(forKey: "pngcut.gif.frame-rate") as? Int, 17)
        XCTAssertEqual(preferences.string(forKey: "pngcut.gif.frame-rate-kind"), "custom")
        XCTAssertEqual(preferences.string(forKey: "pngcut.gif.loop"), "forever")
        XCTAssertEqual(AppModel(preferences: preferences).settings.gif, GIFSettings(
            isPNGSequenceConversionEnabled: false,
            frameRate: .custom(17),
            loop: .forever
        ))
    }

    func testRejectingNoSequencePromptBlocksFIFOUntilNoticeIsDismissed() async throws {
        let directory = try makeTemporaryDirectory("PngCut-NoticeFIFOTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeSourceFile(named: "first.png", in: directory)
        let second = try makeSourceFile(named: "second.png", in: directory)
        let detector = CountingNoSequenceDetector()
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: detector
        )

        model.add(urls: [first])
        model.add(urls: [second])
        let showedFirstPrompt = await waitUntil { model.activeImportDecision != nil }
        let analyzedBothImports = await waitUntil { detector.detectionCount == 2 }
        XCTAssertTrue(showedFirstPrompt)
        XCTAssertTrue(analyzedBothImports)
        await Task.yield()

        model.resolveNoSequenceDecision(compressInstead: false)

        XCTAssertEqual(model.activeImportDecision, .noSequenceNotice)

        model.dismissNoSequenceNotice()
        let showedSecondPrompt = await waitUntil {
            guard case let .noSequenceDetected(resolution)? = model.activeImportDecision else { return false }
            return resolution.regularImages.map(\.fileURL) == [second]
        }
        XCTAssertTrue(showedSecondPrompt)
    }

    func testSequenceDimensionPreflightRunsOffTheMainThread() async throws {
        let directory = try makeTemporaryDirectory("PngCut-SequencePreflightThreadTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "walk", in: directory)
        let detector = ThreadRecordingSequenceDetector(sequences: [sequence])
        let encoder = ModelSequenceEncoder()
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: detector,
            sequenceEncoderFactory: { encoder }
        )

        model.add(urls: sequence.frameURLs)
        let finished = await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

        XCTAssertTrue(finished)
        XCTAssertEqual(detector.validationThreadWasMain, false)
    }

    func testBlockedFirstDiscoveryKeepsFirstSequencePromptAheadOfSecondImport() async throws {
        let directory = try makeTemporaryDirectory("PngCut-DiscoveryFIFOTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeSequence(named: "first", in: directory)
        let second = try makeSequence(named: "second", in: directory)
        let unexpectedSecondStart = expectation(description: "second discovery starts before the first is released")
        unexpectedSecondStart.isInverted = true
        let expectedSecondStart = expectation(description: "second discovery starts after the first is released")
        let secondStartObserver = SecondDiscoveryStartObserver(
            beforeRelease: unexpectedSecondStart,
            afterRelease: expectedSecondStart
        )
        let detector = BlockingFirstSequenceDetector(
            first: first,
            second: second,
            onSecondDiscoveryStart: { secondStartObserver.recordSecondStart() }
        )
        let model = AppModel(
            loadPersistedSettings: false,
            sequenceDetector: detector,
            compressorFactory: { _ in RecordingModelCompressor(engine: .oxipng, failsFirstCompression: false) }
        )

        model.add(urls: first.frameURLs)
        let startedFirstDiscovery = await waitUntil { detector.firstDiscoveryStarted }
        XCTAssertTrue(startedFirstDiscovery)
        model.add(urls: second.frameURLs)
        await fulfillment(of: [unexpectedSecondStart], timeout: 0.2)
        XCTAssertFalse(detector.secondDiscoveryStartedBeforeFirstRelease)
        secondStartObserver.expectSecondStartAfterRelease()
        detector.releaseFirstDiscovery()
        await fulfillment(of: [expectedSecondStart], timeout: 2)
        XCTAssertFalse(detector.secondDiscoveryStartedBeforeFirstRelease)

        let showedFirstPrompt = await waitUntil {
            guard case let .sequenceDetected(resolution)? = model.activeImportDecision else { return false }
            return resolution.sequences == [first]
        }
        XCTAssertTrue(showedFirstPrompt)

        model.resolveSequenceDecision(convertSequence: false)
        let showedSecondPrompt = await waitUntil {
            guard case let .sequenceDetected(resolution)? = model.activeImportDecision else { return false }
            return resolution.sequences == [second]
        }
        XCTAssertTrue(showedSecondPrompt)
    }

    func testGeneratedGIFOutputPlanningFailureRecordsFailedTaskWithoutInvokingEncoder() async throws {
        let directory = try makeTemporaryDirectory("PngCut-GeneratedGIFOutputFailureTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "walk", in: directory)
        let missingOutputDirectory = directory.appendingPathComponent("missing-output", isDirectory: true)
        let encoder = ModelSequenceEncoder()
        let model = AppModel(
            settings: AppSettings(
                outputPolicy: .customDirectory,
                customOutputDirectory: missingOutputDirectory,
                gif: GIFSettings(isPNGSequenceConversionEnabled: true)
            ),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(sequences: [sequence]),
            sequenceEncoderFactory: { encoder }
        )

        model.add(urls: sequence.frameURLs)
        let recordedFailure = await waitUntil { model.tasks.count == 1 && model.tasks[0].state.isFailed }

        XCTAssertTrue(recordedFailure)
        XCTAssertEqual(model.tasks[0].engine, .gifski)
        XCTAssertFalse(model.tasks[0].isRetryable)
        guard case let .failed(failure) = model.tasks[0].state else {
            return XCTFail("Expected generated GIF output planning to fail")
        }
        XCTAssertEqual(failure.code, .outputPolicyInvalid)
        let calls = await encoder.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testDirectGIFUsesGifsicleAndTheCurrentGlobalMode() async throws {
        let directory = try makeTemporaryDirectory("PngCut-GIFRoutingTests")
        defer { try? FileManager.default.removeItem(at: directory) }

        for mode in [CompressionMode.lossless, .balanced] {
            let source = try makeSourceFile(named: "animation-\(mode.rawValue).gif", in: directory)
            let factory = RecordingCompressorFactory()
            let model = AppModel(
                settings: AppSettings(mode: mode),
                loadPersistedSettings: false,
                sequenceDetector: ModelSequenceDetector(),
                compressorFactory: { engine in factory.compressor(for: engine) }
            )

            model.add(urls: [source])
            let finished = await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

            XCTAssertTrue(finished)
            XCTAssertEqual(factory.requestedEngines, [.gifsicle])
            XCTAssertEqual(model.tasks[0].engine, .gifsicle)
            XCTAssertEqual(model.tasks[0].displayMode, mode)
        }
    }

    func testDetectedSequenceWithConversionDisabledPromptsAndAcceptedConversionUsesGIFSettings() async throws {
        let directory = try makeTemporaryDirectory("PngCut-SequencePromptTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "walk", in: directory)
        let encoder = ModelSequenceEncoder()
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(
                isPNGSequenceConversionEnabled: false,
                frameRate: .custom(17),
                loop: .once
            )),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(sequences: [sequence]),
            sequenceEncoderFactory: { encoder },
            compressorFactory: { _ in RecordingModelCompressor(engine: .oxipng, failsFirstCompression: false) }
        )

        model.add(urls: sequence.frameURLs)
        let showedPrompt = await waitUntil { model.activeImportDecision != nil }

        XCTAssertTrue(showedPrompt)
        guard case let .sequenceDetected(resolution)? = model.activeImportDecision else {
            return XCTFail("Expected a PNG sequence conversion prompt")
        }
        XCTAssertEqual(resolution.regularImages, [])
        XCTAssertEqual(resolution.sequences, [sequence])
        XCTAssertEqual(resolution.totalCandidateFrameCount, 10)
        XCTAssertEqual(resolution.convertMessage, "发现达到阈值的连续编号 PNG（共 10 张），是否转 GIF？")

        model.resolveSequenceDecision(convertSequence: true)
        let finished = await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }

        XCTAssertTrue(finished)
        XCTAssertTrue(model.settings.gif.isPNGSequenceConversionEnabled)
        XCTAssertEqual(model.tasks[0].inputKind, .pngSequence(frameCount: 10))
        XCTAssertEqual(model.tasks[0].format, .gif)
        XCTAssertEqual(model.tasks[0].engine, .gifski)
        XCTAssertEqual(model.tasks[0].displayName, "walk.gif")
        let calls = await encoder.calls()
        XCTAssertEqual(calls, [ModelSequenceEncoder.Call(
            frames: sequence.frameURLs,
            quality: 100,
            frameRate: 17,
            loop: .once
        )])
    }

    func testDetectedSequenceWithConversionDisabledQueuesFramesAsPNGsWhenDeclined() async throws {
        let directory = try makeTemporaryDirectory("PngCut-SequenceDeclineTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "walk", in: directory)
        let factory = RecordingCompressorFactory()
        let model = AppModel(
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(sequences: [sequence]),
            compressorFactory: { engine in factory.compressor(for: engine) }
        )

        model.add(urls: sequence.frameURLs)
        let showedPrompt = await waitUntil { model.activeImportDecision != nil }
        XCTAssertTrue(showedPrompt)
        model.resolveSequenceDecision(convertSequence: false)
        let completedFrames = await waitUntil {
            model.tasks.count == sequence.frameURLs.count && model.tasks.allSatisfy { $0.state == .completed }
        }
        XCTAssertTrue(completedFrames)

        XCTAssertFalse(model.settings.gif.isPNGSequenceConversionEnabled)
        XCTAssertEqual(model.tasks.map(\.sourceURL), sequence.frameURLs)
        XCTAssertTrue(model.tasks.allSatisfy { $0.inputKind == .file && $0.engine == .oxipng })
        XCTAssertEqual(factory.requestedEngines, Array(repeating: .oxipng, count: sequence.frameURLs.count))
    }

    func testDetectedSequenceWithConversionEnabledEncodesDirectlyWithoutPrompt() async throws {
        let directory = try makeTemporaryDirectory("PngCut-SequenceDirectTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "run", in: directory)
        let encoder = ModelSequenceEncoder()
        let model = AppModel(
            settings: AppSettings(mode: .balanced, gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(sequences: [sequence]),
            sequenceEncoderFactory: { encoder },
            compressorFactory: { _ in RecordingModelCompressor(engine: .oxipng, failsFirstCompression: false) }
        )

        model.add(urls: sequence.frameURLs)
        let encoded = await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }
        XCTAssertTrue(encoded)

        XCTAssertNil(model.activeImportDecision)
        XCTAssertEqual(model.tasks[0].engine, .gifski)
        XCTAssertEqual(model.tasks[0].displayMode, .balanced)
        let calls = await encoder.calls()
        XCTAssertEqual(calls.map(\.quality), [80])
    }

    func testRegularImagesWithoutCandidateAndConversionDisabledCompressDirectly() async throws {
        let directory = try makeTemporaryDirectory("PngCut-RegularDirectTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSourceFile(named: "still.png", in: directory)
        let factory = RecordingCompressorFactory()
        let model = AppModel(
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(),
            compressorFactory: { engine in factory.compressor(for: engine) }
        )

        model.add(urls: [source])
        let completed = await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }
        XCTAssertTrue(completed)

        XCTAssertNil(model.activeImportDecision)
        XCTAssertEqual(model.tasks[0].sourceURL, source)
        XCTAssertEqual(model.tasks[0].engine, .oxipng)
    }

    func testRegularImagesWithoutCandidateAndConversionEnabledUnchecksThenCompressesWhenConfirmed() async throws {
        let directory = try makeTemporaryDirectory("PngCut-RegularConfirmTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSourceFile(named: "still.png", in: directory)
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(),
            compressorFactory: { _ in RecordingModelCompressor(engine: .oxipng, failsFirstCompression: false) }
        )

        model.add(urls: [source])
        let showedPrompt = await waitUntil { model.activeImportDecision != nil }
        XCTAssertTrue(showedPrompt)
        guard case .noSequenceDetected? = model.activeImportDecision else {
            return XCTFail("Expected a no-sequence decision")
        }
        model.resolveNoSequenceDecision(compressInstead: true)
        let completed = await waitUntil { model.tasks.count == 1 && model.tasks[0].state == .completed }
        XCTAssertTrue(completed)

        XCTAssertFalse(model.settings.gif.isPNGSequenceConversionEnabled)
        XCTAssertEqual(model.tasks[0].sourceURL, source)
    }

    func testRegularImagesWithoutCandidateAndConversionEnabledShowNoticeWhenDeclined() async throws {
        let directory = try makeTemporaryDirectory("PngCut-RegularDeclineTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try makeSourceFile(named: "still.png", in: directory)
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector()
        )

        model.add(urls: [source])
        let showedPrompt = await waitUntil { model.activeImportDecision != nil }
        XCTAssertTrue(showedPrompt)
        model.resolveNoSequenceDecision(compressInstead: false)

        XCTAssertEqual(model.activeImportDecision, .noSequenceNotice)
        XCTAssertTrue(model.settings.gif.isPNGSequenceConversionEnabled)
        XCTAssertTrue(model.tasks.isEmpty)
        model.dismissNoSequenceNotice()
        XCTAssertNil(model.activeImportDecision)
    }

    func testDecliningNoSequenceNoticeUnlocksTheNextImport() async throws {
        let directory = try makeTemporaryDirectory("PngCut-DecisionRecoveryTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeSourceFile(named: "first.png", in: directory)
        let second = try makeSourceFile(named: "second.png", in: directory)
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector()
        )

        model.add(urls: [first])
        let showedFirstDecision = await waitUntil { model.activeImportDecision != nil }
        XCTAssertTrue(showedFirstDecision)
        guard case .noSequenceDetected? = model.activeImportDecision else {
            return XCTFail("Expected the no-sequence decision")
        }

        model.resolveNoSequenceDecision(compressInstead: false)
        XCTAssertEqual(model.activeImportDecision, .noSequenceNotice)
        XCTAssertTrue(model.settings.gif.isPNGSequenceConversionEnabled)
        XCTAssertTrue(model.tasks.isEmpty)

        model.dismissNoSequenceNotice()
        XCTAssertNil(model.activeImportDecision)

        model.add(urls: [second])
        let showedSecondDecision = await waitUntil { model.activeImportDecision != nil }
        XCTAssertTrue(showedSecondDecision)
        guard case let .noSequenceDetected(resolution)? = model.activeImportDecision else {
            return XCTFail("Expected the second import to be accepted")
        }
        XCTAssertEqual(resolution.regularImages.map(\.fileURL), [second])
    }

    func testMixedImportConvertsSequenceAndRoutesStandalonePNGAndGIFAsRegularFiles() async throws {
        let directory = try makeTemporaryDirectory("PngCut-MixedImportTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "walk", in: directory)
        let standalonePNG = try makeSourceFile(named: "cover.png", in: directory)
        let standaloneGIF = try makeSourceFile(named: "already.gif", in: directory)
        let factory = RecordingCompressorFactory()
        let encoder = ModelSequenceEncoder()
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(sequences: [sequence]),
            sequenceEncoderFactory: { encoder },
            compressorFactory: { engine in factory.compressor(for: engine) }
        )

        model.add(urls: sequence.frameURLs + [standalonePNG, standaloneGIF])
        let completed = await waitUntil {
            model.tasks.count == 3 && model.tasks.allSatisfy { $0.state == .completed }
        }
        XCTAssertTrue(completed)

        XCTAssertEqual(model.tasks.map(\.engine), [.gifski, .oxipng, .gifsicle])
        XCTAssertEqual(model.tasks[0].sourceURLs, sequence.frameURLs)
        XCTAssertEqual(model.tasks[1].sourceURL, standalonePNG)
        XCTAssertEqual(model.tasks[2].sourceURL, standaloneGIF)
        XCTAssertEqual(factory.requestedEngines, [.oxipng, .gifsicle])
    }

    func testDimensionMismatchRecordsANonRetryableFailedGIFTaskAndContinuesRegularImports() async throws {
        let directory = try makeTemporaryDirectory("PngCut-SequenceMismatchTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "broken", in: directory, contents: Data("frame".utf8))
        let regular = try makeSourceFile(named: "cover.png", in: directory, contents: Data("regular".utf8))
        let detector = ModelSequenceDetector(sequences: [sequence], invalidOutputNames: [sequence.outputFileName])
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: detector,
            compressorFactory: { _ in RecordingModelCompressor(engine: .oxipng, failsFirstCompression: false) }
        )

        model.add(urls: sequence.frameURLs + [regular])
        let finished = await waitUntil {
            model.tasks.count == 2 && model.tasks.contains(where: { $0.state.isFailed }) && model.tasks.contains(where: { $0.state == .completed })
        }
        XCTAssertTrue(finished)

        guard let failed = model.tasks.first(where: { $0.state.isFailed }) else {
            return XCTFail("Expected a failed GIF task")
        }
        XCTAssertEqual(failed.sourceURLs, sequence.frameURLs)
        XCTAssertEqual(failed.displayName, "broken.gif")
        XCTAssertEqual(failed.inputKind, .pngSequence(frameCount: 10))
        XCTAssertFalse(failed.isRetryable)
        XCTAssertEqual(failed.format, .gif)
        XCTAssertEqual(failed.engine, .gifski)
        XCTAssertEqual(failed.originalFileSize, Int64(sequence.frameURLs.count * Data("frame".utf8).count))
        XCTAssertEqual(failed.state, .failed(CompressionFailure(
            code: .outputInvalid,
            technicalMessage: "帧尺寸不一致，无法转 GIF"
        )))
        XCTAssertEqual(model.tasks.first(where: { $0.state == .completed })?.sourceURL, regular)
    }

    func testFailedOnlySequenceImportStillPublishesItsFailedTask() async throws {
        let directory = try makeTemporaryDirectory("PngCut-FailedOnlySequenceTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sequence = try makeSequence(named: "broken", in: directory)
        let model = AppModel(
            settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(sequences: [sequence], invalidOutputNames: [sequence.outputFileName])
        )

        model.add(urls: sequence.frameURLs)
        let recordedFailure = await waitUntil { model.tasks.count == 1 && model.tasks[0].state.isFailed }
        XCTAssertTrue(recordedFailure)
        XCTAssertFalse(model.tasks[0].isRetryable)
    }

    func testConcurrentImportsKeepSequencePromptsFIFO() async throws {
        let directory = try makeTemporaryDirectory("PngCut-SequenceFIFOTests")
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeSequence(named: "first", in: directory)
        let second = try makeSequence(named: "second", in: directory)
        let model = AppModel(
            loadPersistedSettings: false,
            sequenceDetector: ModelSequenceDetector(sequences: [first, second]),
            compressorFactory: { _ in RecordingModelCompressor(engine: .oxipng, failsFirstCompression: false) }
        )

        model.add(urls: first.frameURLs)
        model.add(urls: second.frameURLs)
        let showedFirstPrompt = await waitUntil { model.activeImportDecision != nil }
        XCTAssertTrue(showedFirstPrompt)
        guard case let .sequenceDetected(firstResolution)? = model.activeImportDecision else {
            return XCTFail("Expected the first prompt")
        }
        XCTAssertEqual(firstResolution.sequences, [first])

        model.resolveSequenceDecision(convertSequence: false)
        let showedSecondPrompt = await waitUntil {
            guard case let .sequenceDetected(resolution)? = model.activeImportDecision else { return false }
            return resolution.sequences == [second]
        }
        XCTAssertTrue(showedSecondPrompt)
    }

    private func makeTemporaryDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSourceFile(named name: String, in directory: URL, contents: Data = Data("source".utf8)) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url)
        return url.standardizedFileURL
    }

    private func makeSequence(named name: String, in directory: URL, contents: Data = Data("frame".utf8)) throws -> PNGSequence {
        let frames = try (1...10).map { frame in
            try makeSourceFile(
                named: "\(name)_\(String(format: "%04d", frame)).png",
                in: directory,
                contents: contents
            )
        }
        return PNGSequence(frameURLs: frames, importedFolderRoot: nil, outputFileName: "\(name).gif")
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
        return condition()
    }
}

private struct ModelSequenceDetector: PNGSequenceDetecting {
    let sequences: [PNGSequence]
    let invalidOutputNames: Set<String>

    init(sequences: [PNGSequence] = [], invalidOutputNames: Set<String> = []) {
        self.sequences = sequences
        self.invalidOutputNames = invalidOutputNames
    }

    func detect(in images: [DiscoveredImage]) -> [PNGSequence] {
        let importedURLs = Set(images.map(\.fileURL))
        return sequences.filter { sequence in
            Set(sequence.frameURLs).isSubset(of: importedURLs)
        }
    }

    func validateFrameDimensions(_ sequence: PNGSequence) throws {
        guard !invalidOutputNames.contains(sequence.outputFileName) else {
            throw CompressionFailure(code: .outputInvalid, technicalMessage: "帧尺寸不一致，无法转 GIF")
        }
    }
}

private final class CountingNoSequenceDetector: PNGSequenceDetecting, @unchecked Sendable {
    private let lock = NSLock()
    private var detectedImports = 0

    func detect(in images: [DiscoveredImage]) -> [PNGSequence] {
        lock.lock()
        detectedImports += 1
        lock.unlock()
        return []
    }

    func validateFrameDimensions(_ sequence: PNGSequence) throws {}

    var detectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return detectedImports
    }
}

private final class ThreadRecordingSequenceDetector: PNGSequenceDetecting, @unchecked Sendable {
    private let sequences: [PNGSequence]
    private let lock = NSLock()
    private var wasValidationOnMainThread: Bool?

    init(sequences: [PNGSequence]) {
        self.sequences = sequences
    }

    func detect(in images: [DiscoveredImage]) -> [PNGSequence] {
        let importedURLs = Set(images.map(\.fileURL))
        return sequences.filter { Set($0.frameURLs).isSubset(of: importedURLs) }
    }

    func validateFrameDimensions(_ sequence: PNGSequence) throws {
        lock.lock()
        wasValidationOnMainThread = Thread.isMainThread
        lock.unlock()
    }

    var validationThreadWasMain: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return wasValidationOnMainThread
    }
}

private final class BlockingFirstSequenceDetector: PNGSequenceDetecting, @unchecked Sendable {
    private let first: PNGSequence
    private let second: PNGSequence
    private let condition = NSCondition()
    private let onSecondDiscoveryStart: () -> Void
    private var hasStartedFirstDiscovery = false
    private var isFirstDiscoveryReleased = false
    private var hasStartedSecondDiscoveryBeforeFirstRelease = false

    init(
        first: PNGSequence,
        second: PNGSequence,
        onSecondDiscoveryStart: @escaping () -> Void = {}
    ) {
        self.first = first
        self.second = second
        self.onSecondDiscoveryStart = onSecondDiscoveryStart
    }

    func detect(in images: [DiscoveredImage]) -> [PNGSequence] {
        let importedURLs = Set(images.map(\.fileURL))
        if Set(first.frameURLs).isSubset(of: importedURLs) {
            condition.lock()
            hasStartedFirstDiscovery = true
            condition.broadcast()
            while !isFirstDiscoveryReleased {
                condition.wait()
            }
            condition.unlock()
            return [first]
        }
        guard Set(second.frameURLs).isSubset(of: importedURLs) else {
            return []
        }
        condition.lock()
        if !isFirstDiscoveryReleased {
            hasStartedSecondDiscoveryBeforeFirstRelease = true
        }
        condition.unlock()
        onSecondDiscoveryStart()
        return [second]
    }

    func validateFrameDimensions(_ sequence: PNGSequence) throws {}

    var firstDiscoveryStarted: Bool {
        condition.lock()
        defer { condition.unlock() }
        return hasStartedFirstDiscovery
    }

    var secondDiscoveryStartedBeforeFirstRelease: Bool {
        condition.lock()
        defer { condition.unlock() }
        return hasStartedSecondDiscoveryBeforeFirstRelease
    }

    func releaseFirstDiscovery() {
        condition.lock()
        isFirstDiscoveryReleased = true
        condition.broadcast()
        condition.unlock()
    }
}

private final class SecondDiscoveryStartObserver: @unchecked Sendable {
    private enum Phase: Equatable {
        case beforeRelease
        case afterRelease
    }

    private let lock = NSLock()
    private let beforeRelease: XCTestExpectation
    private let afterRelease: XCTestExpectation
    private var phase: Phase = .beforeRelease

    init(beforeRelease: XCTestExpectation, afterRelease: XCTestExpectation) {
        self.beforeRelease = beforeRelease
        self.afterRelease = afterRelease
    }

    func expectSecondStartAfterRelease() {
        lock.lock()
        phase = .afterRelease
        lock.unlock()
    }

    func recordSecondStart() {
        lock.lock()
        let expectation = phase == .beforeRelease ? beforeRelease : afterRelease
        lock.unlock()
        expectation.fulfill()
    }
}

private actor ModelSequenceEncoder: GifskiSequenceEncoding {
    struct Call: Equatable, Sendable {
        let frames: [URL]
        let quality: Int
        let frameRate: Int
        let loop: GIFLoop
    }

    private var recordedCalls: [Call] = []

    func encode(
        frames: [URL],
        temporaryDestination: URL,
        quality: Int,
        frameRate: Int,
        loop: GIFLoop,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        recordedCalls.append(Call(frames: frames, quality: quality, frameRate: frameRate, loop: loop))
        try FileManager.default.createDirectory(at: temporaryDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("gif".utf8).write(to: temporaryDestination)
        progress(1)
    }

    func calls() -> [Call] {
        recordedCalls
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
            throw CompressionFailure(code: .engineFailed, technicalMessage: "expected failure")
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
