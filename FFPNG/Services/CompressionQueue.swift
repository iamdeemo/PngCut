import Foundation

actor CompressionQueue {
    typealias StateDidChange = @MainActor ([CompressionTask]) -> Void

    private struct QueuedTask {
        var task: CompressionTask
        var compressor: any ImageCompressor
    }

    private let defaultCompressor: any ImageCompressor
    private let stateDidChange: StateDidChange
    private var queuedTasks: [QueuedTask] = []
    private var worker: Task<Void, Never>?

    init(compressor: any ImageCompressor, stateDidChange: @escaping StateDidChange = { _ in }) {
        self.defaultCompressor = compressor
        self.stateDidChange = stateDidChange
    }

    func enqueue(_ tasks: [CompressionTask], using compressor: (any ImageCompressor)? = nil) async {
        let compressor = compressor ?? defaultCompressor
        queuedTasks.append(contentsOf: tasks.map { task in
            var task = task
            task.state = .queued
            task.progress = 0
            return QueuedTask(task: task, compressor: compressor)
        })
        await publish()
        startWorkerIfNeeded()
    }

    func recordFailed(_ tasks: [CompressionTask], using compressor: any ImageCompressor) async {
        queuedTasks.append(contentsOf: tasks.map { QueuedTask(task: $0, compressor: compressor) })
        await publish()
    }

    func retryFailed(replacingInvalidAPIKeyCompressorWith compressor: (any ImageCompressor)? = nil) async {
        var didResetTask = false
        for index in queuedTasks.indices where queuedTasks[index].task.state.isFailed {
            let isInvalidAPIKey = queuedTasks[index].task.state == .failed(.invalidAPIKey)
            if isInvalidAPIKey, compressor == nil {
                continue
            }
            queuedTasks[index].task.state = .queued
            queuedTasks[index].task.progress = 0
            if isInvalidAPIKey, let compressor {
                queuedTasks[index].compressor = compressor
            }
            didResetTask = true
        }

        guard didResetTask else {
            return
        }

        await publish()
        startWorkerIfNeeded()
    }

    func tasks() -> [CompressionTask] {
        queuedTasks.map(\.task)
    }

    func waitUntilIdle() async {
        while worker != nil {
            await Task.yield()
        }
    }

    private func startWorkerIfNeeded() {
        guard worker == nil else {
            return
        }

        worker = Task { [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        while let taskIndex = queuedTasks.firstIndex(where: { $0.task.state == .queued }) {
            queuedTasks[taskIndex].task.state = .processing
            queuedTasks[taskIndex].task.progress = 0
            await publish()

            let queuedTask = queuedTasks[taskIndex]
            let task = queuedTask.task
            let queue = self
            guard let finalURL = task.outputURL, let temporaryURL = task.temporaryOutputURL else {
                queuedTasks[taskIndex].task.state = .failed(.outputValidation("The task is missing an output destination."))
                await publish()
                continue
            }

            do {
                try await queuedTask.compressor.compress(
                    source: task.sourceURL,
                    temporaryDestination: temporaryURL,
                    progress: { [queue, taskID = task.id] progress in
                        Task {
                            await queue.updateProgress(for: taskID, progress: progress)
                        }
                    }
                )

                try validateTemporaryOutput(at: temporaryURL)
                try PreparedOutput(
                    finalURL: finalURL,
                    temporaryURL: temporaryURL,
                    allowsReplacingExistingFile: task.allowsReplacingExistingOutput
                ).commit()
                queuedTasks[taskIndex].task.state = .completed
                queuedTasks[taskIndex].task.progress = 1
            } catch let failure as CompressionFailure {
                removeTemporaryOutput(at: temporaryURL)
                queuedTasks[taskIndex].task.state = .failed(failure)
            } catch {
                removeTemporaryOutput(at: temporaryURL)
                queuedTasks[taskIndex].task.state = .failed(.localExecution(error.localizedDescription))
            }

            await publish()
        }

        worker = nil
    }

    private func updateProgress(for taskID: UUID, progress: Double) async {
        guard let index = queuedTasks.firstIndex(where: { $0.task.id == taskID }),
              queuedTasks[index].task.state == .processing else {
            return
        }

        queuedTasks[index].task.progress = min(max(progress, 0), 1)
        await publish()
    }

    private func validateTemporaryOutput(at url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw CompressionFailure.outputValidation("The compressor did not create an output file.")
        }
        guard (values.fileSize ?? 0) > 0 else {
            throw CompressionFailure.outputValidation("The compressor created an empty output file.")
        }
    }

    private func removeTemporaryOutput(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func publish() async {
        await stateDidChange(queuedTasks.map(\.task))
    }
}
