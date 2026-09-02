import XCTest
@testable import PngCut

final class CompressionQueueTests: XCTestCase {
    func testPNGSequenceTaskRetainsItsGeneratedGIFMetadataAndAllFrameSources() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-CompressionTaskSequenceTests-\(UUID().uuidString)", isDirectory: true)
        let firstFrame = directory.appendingPathComponent("frames/first.png")
        let secondFrame = directory.appendingPathComponent("frames/../frames/second.png")
        let task = CompressionTask(
            sourceURL: firstFrame,
            sourceURLs: [firstFrame, secondFrame],
            displayName: "walk.gif",
            inputKind: .pngSequence(frameCount: 2),
            isRetryable: false,
            originalFileSize: 1_024
        )

        XCTAssertEqual(task.sourceURL, firstFrame.standardizedFileURL)
        XCTAssertEqual(task.sourceURLs, [
            firstFrame.standardizedFileURL,
            secondFrame.standardizedFileURL
        ])
        XCTAssertEqual(task.displayName, "walk.gif")
        XCTAssertEqual(task.inputKind, CompressionTaskInputKind.pngSequence(frameCount: 2))
        XCTAssertEqual(task.originalFileSize, 1_024)
        XCTAssertFalse(task.isRetryable)
    }

    func testSingleFileTaskKeepsCompatibilityDefaults() {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-CompressionTaskDefaults/../source.png")
        let task = CompressionTask(sourceURL: source)

        XCTAssertEqual(task.sourceURL, source.standardizedFileURL)
        XCTAssertEqual(task.sourceURLs, [source.standardizedFileURL])
        XCTAssertEqual(task.displayName, "source.png")
        XCTAssertEqual(task.inputKind, CompressionTaskInputKind.file)
        XCTAssertTrue(task.isRetryable)
    }

    func testQueueStartsSecondTaskOnlyAfterFirstSettles() async throws {
        let first = makeTask(named: "first")
        let second = makeTask(named: "second")
        let compressor = ControlledCompressor(outcomes: [.waitThenSucceed, .succeed])
        let queue = CompressionQueue(compressor: compressor)

        await queue.enqueue([first, second])
        await compressor.waitUntilStarted(count: 1)

        let startedBeforeRelease = await compressor.startedSources()
        let statesBeforeRelease = await queue.tasks().map(\.state)
        XCTAssertEqual(startedBeforeRelease, [first.sourceURL])
        XCTAssertEqual(statesBeforeRelease, [.processing, .queued])

        await compressor.releaseWaitingCompression()
        await queue.waitUntilIdle()

        let startedAfterRelease = await compressor.startedSources()
        let completedStates = await queue.tasks().map(\.state)
        XCTAssertEqual(startedAfterRelease, [first.sourceURL, second.sourceURL])
        XCTAssertEqual(completedStates, [.completed, .completed])
    }

    func testQueueContinuesAfterIndividualTaskFailure() async throws {
        let failing = makeTask(named: "failing")
        let succeeding = makeTask(named: "succeeding")
        let compressor = ControlledCompressor(outcomes: [.fail(CompressionFailure(
            code: .engineFailed,
            technicalMessage: "oxipng exited 1"
        )), .succeed])
        let queue = CompressionQueue(compressor: compressor)

        await queue.enqueue([failing, succeeding])
        await queue.waitUntilIdle()

        let startedSources = await compressor.startedSources()
        let states = await queue.tasks().map(\.state)
        XCTAssertEqual(startedSources, [failing.sourceURL, succeeding.sourceURL])
        XCTAssertEqual(states, [
            .failed(CompressionFailure(code: .engineFailed, technicalMessage: "oxipng exited 1")),
            .completed
        ])
    }

    func testRetryOnlyRunsFailedTasks() async throws {
        let failing = makeTask(named: "failing")
        let succeeding = makeTask(named: "succeeding")
        let compressor = ControlledCompressor(outcomes: [
            .fail(CompressionFailure(code: .engineFailed, technicalMessage: "offline")),
            .succeed,
            .succeed
        ])
        let queue = CompressionQueue(compressor: compressor)

        await queue.enqueue([failing, succeeding])
        await queue.waitUntilIdle()
        await queue.retryFailed()
        await queue.waitUntilIdle()

        let startedSources = await compressor.startedSources()
        let states = await queue.tasks().map(\.state)
        XCTAssertEqual(startedSources, [
            failing.sourceURL,
            succeeding.sourceURL,
            failing.sourceURL
        ])
        XCTAssertEqual(states, [.completed, .completed])
    }

    func testRetryKeepsTheFailedTasksCompressor() async throws {
        let failed = makeTask(named: "failed")
        let losslessCompressor = ControlledCompressor(outcomes: [.fail(CompressionFailure(
            code: .engineFailed,
            technicalMessage: "failed"
        )), .succeed])
        let queue = CompressionQueue(compressor: losslessCompressor)

        await queue.enqueue([failed])
        await queue.waitUntilIdle()
        await queue.retryFailed()
        await queue.waitUntilIdle()

        let losslessSources = await losslessCompressor.startedSources()
        let states = await queue.tasks().map(\.state)
        XCTAssertEqual(losslessSources, [failed.sourceURL, failed.sourceURL])
        XCTAssertEqual(states, [.completed])
    }

    func testRetryLeavesNonRetryableFailedTaskUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-NonRetryableTaskTests-\(UUID().uuidString)", isDirectory: true)
        let failed = CompressionTask(
            sourceURL: directory.appendingPathComponent("frame-01.png"),
            sourceURLs: (0..<10).map { directory.appendingPathComponent("frame-\($0).png") },
            inputKind: .pngSequence(frameCount: 10),
            isRetryable: false,
            outputURL: directory.appendingPathComponent("animation.gif"),
            temporaryOutputURL: directory.appendingPathComponent(".animation.tmp.gif")
        )
        let compressor = ControlledCompressor(outcomes: [.fail(CompressionFailure(
            code: .engineFailed,
            technicalMessage: "invalid frames"
        ))])
        let queue = CompressionQueue(compressor: compressor)

        await queue.enqueue([failed])
        await queue.waitUntilIdle()
        await queue.retryFailed()
        await queue.waitUntilIdle()

        let startedSources = await compressor.startedSources()
        let states = await queue.tasks().map(\.state)
        XCTAssertEqual(startedSources, [failed.sourceURL])
        XCTAssertEqual(states, [
            .failed(CompressionFailure(code: .engineFailed, technicalMessage: "invalid frames"))
        ])
    }

    func testQueueRunsPNGSequenceOperationWithAllFrameSources() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-SequenceOperationTests-\(UUID().uuidString)", isDirectory: true)
        let frames = (0..<10).map { directory.appendingPathComponent("frame-\($0).png") }
        let task = CompressionTask(
            sourceURL: frames[0],
            sourceURLs: frames,
            inputKind: .pngSequence(frameCount: frames.count),
            outputURL: directory.appendingPathComponent("animation.gif"),
            temporaryOutputURL: directory.appendingPathComponent(".animation.tmp.gif")
        )
        let encoder = RecordingSequenceEncoder()
        let queue = CompressionQueue(compressor: FixedOutputCompressor(data: Data("unused".utf8)))

        await queue.enqueue([
            CompressionQueue.WorkItem(
                task: task,
                operation: .pngSequence(encoder, quality: 100, frameRate: 30, loop: .forever)
            )
        ])
        await queue.waitUntilIdle()

        let receivedFrames = await encoder.frames()
        let states = await queue.tasks().map(\.state)
        XCTAssertEqual(receivedFrames, frames.map(\.standardizedFileURL))
        XCTAssertEqual(states, [.completed])
    }

    func testOverwriteNoChangeLeavesTheSourceEntityAndMetadataUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-CompressionQueueNoChangeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let temporary = directory.appendingPathComponent(".source.pngcut.tmp.png")
        try Data("original source".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: source.path)
        let beforeAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        let beforeInode = beforeAttributes[.systemFileNumber] as? NSNumber
        let beforeModificationDate = beforeAttributes[.modificationDate] as? Date
        let task = CompressionTask(
            sourceURL: source,
            outputURL: source,
            temporaryOutputURL: temporary,
            allowsReplacingExistingOutput: true
        )
        let queue = CompressionQueue(compressor: NoChangeCompressor())

        await queue.enqueue([task])
        await queue.waitUntilIdle()

        let tasks = await queue.tasks()
        let completedTask = try XCTUnwrap(tasks.first)
        let afterAttributes = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual(completedTask.state, .completed)
        XCTAssertEqual(completedTask.outputURL, source.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: source), Data("original source".utf8))
        XCTAssertEqual(afterAttributes[.systemFileNumber] as? NSNumber, beforeInode)
        XCTAssertEqual(afterAttributes[.modificationDate] as? Date, beforeModificationDate)
        XCTAssertEqual(afterAttributes[.posixPermissions] as? NSNumber, beforeAttributes[.posixPermissions] as? NSNumber)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
    }

    func testCompletedTaskRetainsSizeSnapshotAfterOutputIsDeleted() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-CompressionQueueSizeSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let output = directory.appendingPathComponent("source_pngcut.png")
        let temporary = directory.appendingPathComponent(".source_pngcut.tmp.png")
        let sourceData = Data(repeating: 1, count: 200)
        let compressedData = Data(repeating: 2, count: 80)
        try sourceData.write(to: source)
        let task = CompressionTask(sourceURL: source, outputURL: output, temporaryOutputURL: temporary)
        let queue = CompressionQueue(compressor: FixedOutputCompressor(data: compressedData))

        await queue.enqueue([task])
        await queue.waitUntilIdle()
        let tasks = await queue.tasks()
        let completedTask = try XCTUnwrap(tasks.first)
        try FileManager.default.removeItem(at: output)

        XCTAssertEqual(completedTask.originalFileSize, Int64(sourceData.count))
        XCTAssertEqual(completedTask.compressedFileSize, Int64(compressedData.count))
    }

    func testCompressionFailureKeepsItsCodeAndTechnicalMessage() {
        let engineFailure = CompressionFailure(code: .engineFailed, technicalMessage: "failed")
        let outputFailure = CompressionFailure(code: .outputInvalid, technicalMessage: "missing output")

        XCTAssertEqual(engineFailure.code, .engineFailed)
        XCTAssertEqual(engineFailure.technicalMessage, "failed")
        XCTAssertEqual(outputFailure.code, .outputInvalid)
        XCTAssertEqual(outputFailure.technicalMessage, "missing output")
    }

    private func makeTask(named name: String) -> CompressionTask {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-CompressionQueueTests-\(UUID().uuidString)", isDirectory: true)
        let source = directory.appendingPathComponent("\(name).png")
        let temporary = directory.appendingPathComponent(".\(name)-optimized.tmp.png")
        let output = directory.appendingPathComponent("\(name)-optimized.png")
        return CompressionTask(sourceURL: source, outputURL: output, temporaryOutputURL: temporary)
    }
}

private actor ControlledCompressor: ImageCompressor {
    enum Outcome {
        case waitThenSucceed
        case succeed
        case fail(CompressionFailure)
    }

    private var outcomes: [Outcome]
    private var sources: [URL] = []
    private var waitingContinuation: CheckedContinuation<Void, Never>?

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func compress(source: URL, temporaryDestination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> CompressionOutcome {
        sources.append(source)
        let outcome = outcomes.removeFirst()
        progress(0.5)

        switch outcome {
        case .waitThenSucceed:
            await withCheckedContinuation { continuation in
                waitingContinuation = continuation
            }
            try writeOutput(to: temporaryDestination)
            return .compressed
        case .succeed:
            try writeOutput(to: temporaryDestination)
            return .compressed
        case .fail(let failure):
            throw failure
        }
    }

    func startedSources() -> [URL] {
        sources
    }

    func waitUntilStarted(count: Int) async {
        while sources.count < count {
            await Task.yield()
        }
    }

    func releaseWaitingCompression() {
        waitingContinuation?.resume()
        waitingContinuation = nil
    }

    private func writeOutput(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("optimized".utf8).write(to: url)
    }
}

private struct NoChangeCompressor: ImageCompressor {
    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        progress(1)
        return .noChange
    }
}

private struct FixedOutputCompressor: ImageCompressor {
    let data: Data

    func compress(
        source: URL,
        temporaryDestination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CompressionOutcome {
        try data.write(to: temporaryDestination)
        progress(1)
        return .compressed
    }
}

private actor RecordingSequenceEncoder: GifskiSequenceEncoding {
    private var receivedFrames: [URL] = []

    func encode(
        frames: [URL],
        temporaryDestination: URL,
        quality: Int,
        frameRate: Int,
        loop: GIFLoop,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        receivedFrames = frames
        try FileManager.default.createDirectory(at: temporaryDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("gif".utf8).write(to: temporaryDestination)
        progress(1)
    }

    func frames() -> [URL] {
        receivedFrames
    }
}
