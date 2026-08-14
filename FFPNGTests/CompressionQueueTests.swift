import XCTest
@testable import FFPNG

final class CompressionQueueTests: XCTestCase {
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
        let compressor = ControlledCompressor(outcomes: [.fail(.localExecution("oxipng exited 1")), .succeed])
        let queue = CompressionQueue(compressor: compressor)

        await queue.enqueue([failing, succeeding])
        await queue.waitUntilIdle()

        let startedSources = await compressor.startedSources()
        let states = await queue.tasks().map(\.state)
        XCTAssertEqual(startedSources, [failing.sourceURL, succeeding.sourceURL])
        XCTAssertEqual(states, [
            .failed(.localExecution("oxipng exited 1")),
            .completed
        ])
    }

    func testRetryOnlyRunsFailedTasks() async throws {
        let failing = makeTask(named: "failing")
        let succeeding = makeTask(named: "succeeding")
        let compressor = ControlledCompressor(outcomes: [
            .fail(.transport("offline")),
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

    func testRetryKeepsOriginalCompressorForOrdinaryFailures() async throws {
        let failed = makeTask(named: "failed")
        let losslessCompressor = ControlledCompressor(outcomes: [.fail(.localExecution("failed")), .succeed])
        let balancedCompressor = ControlledCompressor(outcomes: [.succeed])
        let queue = CompressionQueue(compressor: losslessCompressor)

        await queue.enqueue([failed])
        await queue.waitUntilIdle()
        await queue.retryFailed(replacingInvalidAPIKeyCompressorWith: balancedCompressor)
        await queue.waitUntilIdle()

        let losslessSources = await losslessCompressor.startedSources()
        let balancedSources = await balancedCompressor.startedSources()
        let states = await queue.tasks().map(\.state)
        XCTAssertEqual(losslessSources, [failed.sourceURL, failed.sourceURL])
        XCTAssertTrue(balancedSources.isEmpty)
        XCTAssertEqual(states, [.completed])
    }

    func testCompressionFailureCasesRemainTyped() {
        XCTAssertEqual(CompressionFailure.invalidAPIKey, .invalidAPIKey)
        XCTAssertEqual(CompressionFailure.quotaExceeded, .quotaExceeded)
        XCTAssertEqual(CompressionFailure.apiResponse(statusCode: 500, message: "unexpected"), .apiResponse(statusCode: 500, message: "unexpected"))
        XCTAssertEqual(CompressionFailure.outputValidation("missing output"), .outputValidation("missing output"))
    }

    private func makeTask(named name: String) -> CompressionTask {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FFPNG-CompressionQueueTests-\(UUID().uuidString)", isDirectory: true)
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

    func compress(source: URL, temporaryDestination: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        sources.append(source)
        let outcome = outcomes.removeFirst()
        progress(0.5)

        switch outcome {
        case .waitThenSucceed:
            await withCheckedContinuation { continuation in
                waitingContinuation = continuation
            }
            try writeOutput(to: temporaryDestination)
        case .succeed:
            try writeOutput(to: temporaryDestination)
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
