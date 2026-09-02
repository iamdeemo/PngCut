using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Core.Services;
using PngCut.Engine;

namespace PngCut.Tests;

public class CompressionQueueTests
{
    private string _directory = null!;

    [SetUp]
    public void SetUp()
    {
        _directory = Path.Combine(Path.GetTempPath(), "PngCut-Queue-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_directory);
    }

    [TearDown]
    public void TearDown()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, true);
        }
    }

    [Test]
    public async Task Queue_processes_tasks_serially()
    {
        var runner = new RecordingRunner();
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var first = NewPngTask("first.png");
        var second = NewPngTask("second.png");

        _ = queue.EnqueueAsync(first);
        _ = queue.EnqueueAsync(second);
        await queue.WaitForIdleAsync();

        Assert.That(runner.MaximumConcurrentRuns, Is.EqualTo(1));
        Assert.That(first.State, Is.EqualTo(TaskState.Completed));
        Assert.That(second.State, Is.EqualTo(TaskState.Completed));
    }

    [Test]
    public async Task Failure_records_a_Chinese_error_and_the_queue_continues()
    {
        var runner = new RecordingRunner(exitCodes: new[] { 1, 0 });
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var failed = NewPngTask("failed.png");
        var completed = NewPngTask("completed.png");

        _ = queue.EnqueueAsync(failed);
        _ = queue.EnqueueAsync(completed);
        await queue.WaitForIdleAsync();

        Assert.That(failed.State, Is.EqualTo(TaskState.Failed));
        Assert.That(failed.ErrorCode, Is.EqualTo(FailureCode.EngineFailed));
        Assert.That(failed.ErrorMessage, Is.EqualTo("压缩程序执行失败。"));
        Assert.That(completed.State, Is.EqualTo(TaskState.Completed));
    }

    [Test]
    public async Task Engine_stderr_is_not_exposed_in_the_user_visible_failure_reason()
    {
        var runner = new RecordingRunner(
            exitCodes: new[] { 1 },
            standardError: @"engine could not read C:\secret\input.png");
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var task = NewPngTask("private.png");

        await queue.EnqueueAsync(task);

        Assert.That(task.State, Is.EqualTo(TaskState.Failed));
        Assert.That(task.ErrorCode, Is.EqualTo(FailureCode.EngineFailed));
        Assert.That(task.ErrorMessage, Is.EqualTo("压缩程序执行失败。"));
        Assert.That(task.ErrorMessage, Does.Not.Contain(@"C:\secret\input.png"));
    }

    [Test]
    public async Task Cleanup_delete_failure_does_not_mask_the_compression_failure_or_stop_the_queue()
    {
        var runner = new RecordingRunner(exitCodes: new[] { 1, 0 });
        var queue = new CompressionQueue(
            runner,
            new EngineResolver(_directory, true),
            deleteFile: _ => throw new IOException("cleanup failed"));
        var failed = NewPngTask("cleanup-failed.png");
        var completed = NewPngTask("after-cleanup-failure.png");

        _ = queue.EnqueueAsync(failed);
        _ = queue.EnqueueAsync(completed);
        await queue.WaitForIdleAsync();

        Assert.That(failed.State, Is.EqualTo(TaskState.Failed));
        Assert.That(failed.ErrorCode, Is.EqualTo(FailureCode.EngineFailed));
        Assert.That(failed.ErrorMessage, Is.EqualTo("压缩程序执行失败。"));
        Assert.That(completed.State, Is.EqualTo(TaskState.Completed));
        Assert.That(queue.ReservedOutputCount, Is.EqualTo(1));
    }

    [Test]
    public async Task Retry_requested_during_failure_transition_is_queued_after_registration_is_released()
    {
        Task? retryTask = null;
        CompressionQueue? queue = null;
        var runner = new RecordingRunner(exitCodes: new[] { 1, 0 });
        queue = new CompressionQueue(
            runner,
            new EngineResolver(_directory, true),
            onTaskFailed: task => retryTask = queue!.RetryAsync(task));
        var task = NewPngTask("transition-retry.png");

        await queue.EnqueueAsync(task);
        Assert.That(retryTask, Is.Not.Null);
        await retryTask!;

        Assert.That(task.State, Is.EqualTo(TaskState.Completed));
        Assert.That(runner.Files.Count, Is.EqualTo(2));
        Assert.That(queue.ReservedOutputCount, Is.EqualTo(1));
    }

    [Test]
    public async Task Duplicate_enqueue_of_the_same_task_is_rejected_before_it_starts()
    {
        var queue = new CompressionQueue(new RecordingRunner(), new EngineResolver(_directory, true));
        var task = NewPngTask("duplicate.png");

        _ = queue.EnqueueAsync(task);

        Assert.That(() => queue.EnqueueAsync(task), Throws.TypeOf<InvalidOperationException>());
        await queue.WaitForIdleAsync();
        Assert.That(task.State, Is.EqualTo(TaskState.Completed));
    }

    [Test]
    public async Task Retry_failed_task_keeps_its_assigned_engine()
    {
        var runner = new RecordingRunner(exitCodes: new[] { 1, 0 });
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var task = NewPngTask("retry.png", EngineKind.Pngquant);

        await queue.EnqueueAsync(task);
        await queue.WaitForIdleAsync();
        await queue.RetryAsync(task);
        await queue.WaitForIdleAsync();

        Assert.That(task.Engine, Is.EqualTo(EngineKind.Pngquant));
        Assert.That(task.State, Is.EqualTo(TaskState.Completed));
        Assert.That(runner.Files.All(path => path.EndsWith("pngquant.exe", StringComparison.OrdinalIgnoreCase)), Is.True);
    }

    [TestCase(98)]
    [TestCase(99)]
    public async Task Pngquant_no_change_removes_temporary_output_and_keeps_source_when_overwriting(int exitCode)
    {
        var runner = new RecordingRunner(
            exitCodes: new[] { exitCode },
            temporaryOutputs: new[] { TemporaryOutput.Valid });
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var task = NewPngTask("source.png", EngineKind.Pngquant, OutputMode.Overwrite);
        var originalSize = new FileInfo(task.SourcePath).Length;
        var originalContent = File.ReadAllBytes(task.SourcePath);

        await queue.EnqueueAsync(task);
        await queue.WaitForIdleAsync();

        Assert.That(task.OutputPath, Is.EqualTo(task.SourcePath));
        Assert.That(task.State, Is.EqualTo(TaskState.Completed));
        Assert.That(task.OriginalBytes, Is.EqualTo(originalSize));
        Assert.That(task.CompressedBytes, Is.EqualTo(originalSize));
        Assert.That(File.ReadAllBytes(task.SourcePath), Is.EqualTo(originalContent));
        Assert.That(new FileInfo(task.SourcePath).Length, Is.EqualTo(originalSize));
        Assert.That(runner.TemporaryPaths.All(path => !File.Exists(path)), Is.True);
    }

    [Test]
    public async Task Non_overwrite_outputs_are_reserved_without_clobbering_existing_or_queued_destinations()
    {
        var originalOutput = Path.Combine(_directory, "image_pngcut.png");
        File.WriteAllText(originalOutput, "unrelated");
        var runner = new RecordingRunner();
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var first = NewPngTask("image.png");
        var second = NewPngTask("image.png");

        _ = queue.EnqueueAsync(first);
        _ = queue.EnqueueAsync(second);
        await queue.WaitForIdleAsync();

        Assert.That(File.ReadAllText(originalOutput), Is.EqualTo("unrelated"));
        Assert.That(first.OutputPath, Is.Not.EqualTo(second.OutputPath));
        Assert.That(first.OutputPath, Does.EndWith("image_pngcut-2.png"));
        Assert.That(second.OutputPath, Does.EndWith("image_pngcut-3.png"));
    }

    [Test]
    public async Task Temporary_output_uses_a_unique_sibling_name_and_completion_keeps_size_snapshot()
    {
        var runner = new RecordingRunner();
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var task = NewPngTask("snapshot.png");
        var originalSize = new FileInfo(task.SourcePath).Length;

        await queue.EnqueueAsync(task);
        await queue.WaitForIdleAsync();
        File.Delete(task.OutputPath!);

        Assert.That(Path.GetFileName(runner.TemporaryPaths.Single()),
            Does.Match(@"^\.snapshot_pngcut\.[0-9a-f]{32}\.tmp\.png$"));
        Assert.That(task.OriginalBytes, Is.EqualTo(originalSize));
        Assert.That(task.CompressedBytes, Is.EqualTo(5));
    }

    [Test]
    public async Task Folder_import_context_preserves_the_relative_output_path()
    {
        var selectedRoot = Path.Combine(_directory, "art");
        var nested = Path.Combine(selectedRoot, "icons");
        Directory.CreateDirectory(nested);
        var source = Path.Combine(nested, "logo.png");
        File.WriteAllText(source, "original-image");

        var task = FileDiscovery.Discover(new[] { selectedRoot }, CompressionMode.Lossless)
            .Tasks.Single();
        var queue = new CompressionQueue(new RecordingRunner(), new EngineResolver(_directory, true));

        await queue.EnqueueAsync(task);
        await queue.WaitForIdleAsync();

        Assert.That(task.State, Is.EqualTo(TaskState.Completed));
        Assert.That(
            task.OutputPath,
            Is.EqualTo(Path.Combine(_directory, "art_pngcut", "icons", "logo.png")));
    }

    [TestCase(TemporaryOutput.Missing)]
    [TestCase(TemporaryOutput.Empty)]
    public async Task Invalid_temporary_output_fails_without_committing_and_the_queue_continues(TemporaryOutput invalidOutput)
    {
        var runner = new RecordingRunner(temporaryOutputs: new[] { invalidOutput, TemporaryOutput.Valid });
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var failed = NewPngTask("invalid.png");
        var completed = NewPngTask("next.png");
        var originalContent = File.ReadAllBytes(failed.SourcePath);
        var originalSize = new FileInfo(failed.SourcePath).Length;
        var expectedFinal = Path.Combine(_directory, "invalid_pngcut.png");

        _ = queue.EnqueueAsync(failed);
        _ = queue.EnqueueAsync(completed);
        await queue.WaitForIdleAsync();

        Assert.That(failed.State, Is.EqualTo(TaskState.Failed));
        Assert.That(failed.ErrorCode, Is.EqualTo(FailureCode.OutputInvalid));
        Assert.That(File.Exists(expectedFinal), Is.False);
        Assert.That(runner.TemporaryPaths.All(path => !File.Exists(path)), Is.True);
        Assert.That(File.ReadAllBytes(failed.SourcePath), Is.EqualTo(originalContent));
        Assert.That(new FileInfo(failed.SourcePath).Length, Is.EqualTo(originalSize));
        Assert.That(completed.State, Is.EqualTo(TaskState.Completed));
    }

    [Test]
    public async Task Failed_task_releases_its_destination_so_retry_reuses_it_without_growing_reservations()
    {
        var runner = new RecordingRunner(exitCodes: new[] { 1, 0 });
        var queue = new CompressionQueue(runner, new EngineResolver(_directory, true));
        var task = NewPngTask("retry-output.png");
        var expectedOutput = Path.Combine(_directory, "retry-output_pngcut.png");

        await queue.EnqueueAsync(task);

        Assert.That(task.State, Is.EqualTo(TaskState.Failed));
        Assert.That(File.Exists(expectedOutput), Is.False);
        Assert.That(queue.ReservedOutputCount, Is.EqualTo(0));

        await queue.RetryAsync(task);

        Assert.That(task.State, Is.EqualTo(TaskState.Completed));
        Assert.That(task.OutputPath, Is.EqualTo(expectedOutput));
        Assert.That(queue.ReservedOutputCount, Is.EqualTo(1));
    }

    private CompressionTask NewPngTask(
        string name,
        EngineKind engine = EngineKind.Oxipng,
        OutputMode outputMode = OutputMode.Adjacent)
    {
        var path = Path.Combine(_directory, name);
        File.WriteAllText(path, "original-image");
        return new CompressionTask(path, ImageFormat.Png, CompressionMode.Balanced, engine, outputMode);
    }

    private sealed class RecordingRunner : IProcessRunner
    {
        private readonly Queue<int> _exitCodes;
        private readonly Queue<TemporaryOutput> _temporaryOutputs;
        private readonly string _standardError;
        private int _activeRuns;

        public RecordingRunner(
            IEnumerable<int>? exitCodes = null,
            IEnumerable<TemporaryOutput>? temporaryOutputs = null,
            string standardError = "engine error")
        {
            _exitCodes = new Queue<int>(exitCodes ?? new[] { 0 });
            _temporaryOutputs = new Queue<TemporaryOutput>(temporaryOutputs ?? new[] { TemporaryOutput.Valid });
            _standardError = standardError;
        }

        public List<string> Files { get; } = new();
        public List<string> TemporaryPaths { get; } = new();
        public int MaximumConcurrentRuns { get; private set; }

        public async Task<ProcessResult> RunAsync(string fileName, string arguments)
        {
            Files.Add(fileName);
            var active = ++_activeRuns;
            MaximumConcurrentRuns = Math.Max(MaximumConcurrentRuns, active);
            await Task.Yield();
            var temporaryPath = ParseTemporaryPath(arguments);
            TemporaryPaths.Add(temporaryPath);
            var temporaryOutput = _temporaryOutputs.Count > 0 ? _temporaryOutputs.Dequeue() : TemporaryOutput.Valid;
            if (temporaryOutput == TemporaryOutput.Valid)
            {
                File.WriteAllText(temporaryPath, "small");
            }
            else if (temporaryOutput == TemporaryOutput.Empty)
            {
                File.Create(temporaryPath).Dispose();
            }
            _activeRuns--;
            return new ProcessResult(_exitCodes.Count > 0 ? _exitCodes.Dequeue() : 0, string.Empty, _standardError);
        }

        private static string ParseTemporaryPath(string arguments)
        {
            var quoted = arguments.Split('"');
            return quoted.First(value => value.EndsWith(".tmp.png", StringComparison.OrdinalIgnoreCase));
        }
    }

    public enum TemporaryOutput
    {
        Valid,
        Missing,
        Empty
    }
}
