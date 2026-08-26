using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using PngCut.Core.Models;
using PngCut.Core.Services;

namespace PngCut.Engine;

public sealed class CompressionQueue
{
    private readonly object _gate = new();
    private readonly IProcessRunner _runner;
    private readonly EngineResolver _resolver;
    private readonly Func<CompressionTask, PreparedOutput>? _outputPreparer;
    private readonly Action<string> _deleteFile;
    private readonly Action<CompressionTask>? _onTaskStarted;
    private readonly Action<CompressionTask>? _onTaskFailed;
    private readonly HashSet<string> _reservedFinalPaths = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<CompressionTask> _enqueuedTasks = new();
    private readonly HashSet<CompressionTask> _scheduledRetries = new();
    private Task _tail = Task.CompletedTask;

    public CompressionQueue(
        IProcessRunner? runner = null,
        EngineResolver? resolver = null,
        Func<CompressionTask, PreparedOutput>? outputPreparer = null,
        Action<string>? deleteFile = null,
        Action<CompressionTask>? onTaskStarted = null,
        Action<CompressionTask>? onTaskFailed = null)
    {
        _runner = runner ?? new ProcessRunner();
        _resolver = resolver ?? new EngineResolver();
        _outputPreparer = outputPreparer;
        _deleteFile = deleteFile ?? File.Delete;
        _onTaskStarted = onTaskStarted;
        _onTaskFailed = onTaskFailed;
    }

    public Task EnqueueAsync(CompressionTask task)
    {
        if (task == null)
        {
            throw new ArgumentNullException(nameof(task));
        }

        lock (_gate)
        {
            var output = RegisterQueuedTask(task);

            _tail = _tail.ContinueWith(
                    _ => ProcessTaskAsync(task, output),
                    TaskScheduler.Default)
                .Unwrap();
            return _tail;
        }
    }

    public Task RetryAsync(CompressionTask task)
    {
        if (task == null)
        {
            throw new ArgumentNullException(nameof(task));
        }

        lock (_gate)
        {
            if (task.State != TaskState.Failed || !_scheduledRetries.Add(task))
            {
                throw new InvalidOperationException("Only failed tasks can be retried once.");
            }

            _tail = _tail.ContinueWith(
                    _ => ProcessRetryAsync(task),
                    TaskScheduler.Default)
                .Unwrap();
            return _tail;
        }
    }

    public Task WaitForIdleAsync()
    {
        lock (_gate)
        {
            return _tail;
        }
    }

    public int ReservedOutputCount
    {
        get
        {
            lock (_gate)
            {
                return _reservedFinalPaths.Count;
            }
        }
    }

    private async Task ProcessTaskAsync(CompressionTask task, PreparedOutput output)
    {
        var completed = false;
        try
        {
            task.StartProcessing();
            NotifyTaskStarted(task);
            var sourceBytes = new FileInfo(task.SourcePath).Length;
            Directory.CreateDirectory(Path.GetDirectoryName(output.FinalPath)!);

            var result = await _runner.RunAsync(
                _resolver.Resolve(task.Engine),
                BuildArguments(task, output.TemporaryPath)).ConfigureAwait(false);
            var outcome = InterpretResult(task, result);
            if (outcome == CompressionOutcome.NoChange)
            {
                DeleteIfPresent(output.TemporaryPath);
                task.Complete(task.SourcePath, sourceBytes, sourceBytes);
                completed = true;
                return;
            }

            EnsureValidOutput(output.TemporaryPath);
            CommitOutput(output);
            var compressedBytes = new FileInfo(output.FinalPath).Length;
            task.Complete(output.FinalPath, sourceBytes, compressedBytes);
            completed = true;
        }
        catch (Exception exception)
        {
            DeleteIfPresent(output.TemporaryPath);

            if (task.State == TaskState.Processing)
            {
                task.Fail("压缩失败：" + FailureReason(exception));
                NotifyTaskFailed(task);
            }
        }
        finally
        {
            lock (_gate)
            {
                _enqueuedTasks.Remove(task);
                if (!completed)
                {
                    _reservedFinalPaths.Remove(output.FinalPath);
                }
            }
        }
    }

    private PreparedOutput PrepareOutput(CompressionTask task)
    {
        var output = _outputPreparer != null
            ? _outputPreparer(task)
            : OutputPolicy.Prepare(
                task.SourcePath,
                task.OutputMode,
                task.CustomOutputDirectory,
                task.SelectedFolderRoot,
                _reservedFinalPaths);

        if (!output.AllowsReplacingExistingFile && _reservedFinalPaths.Contains(output.FinalPath))
        {
            throw new CompressionException("输出文件名已被其他任务占用。");
        }

        _reservedFinalPaths.Add(output.FinalPath);
        return output;
    }

    private PreparedOutput RegisterQueuedTask(CompressionTask task)
    {
        if (task.State != TaskState.Queued || !_enqueuedTasks.Add(task))
        {
            throw new InvalidOperationException("Only queued tasks can be enqueued.");
        }

        try
        {
            return PrepareOutput(task);
        }
        catch
        {
            _enqueuedTasks.Remove(task);
            throw;
        }
    }

    private async Task ProcessRetryAsync(CompressionTask task)
    {
        PreparedOutput output;
        lock (_gate)
        {
            try
            {
                task.Retry();
                output = RegisterQueuedTask(task);
            }
            finally
            {
                _scheduledRetries.Remove(task);
            }
        }

        await ProcessTaskAsync(task, output).ConfigureAwait(false);
    }

    private static CompressionOutcome InterpretResult(CompressionTask task, ProcessResult result)
    {
        if (task.Engine == EngineKind.Pngquant && (result.ExitCode == 98 || result.ExitCode == 99))
        {
            return CompressionOutcome.NoChange;
        }

        if (result.ExitCode != 0)
        {
            throw new CompressionException("压缩程序执行失败。");
        }

        return CompressionOutcome.Compressed;
    }

    private static void EnsureValidOutput(string temporaryPath)
    {
        if (!File.Exists(temporaryPath) || new FileInfo(temporaryPath).Length == 0)
        {
            throw new CompressionException("压缩程序没有生成有效输出文件。");
        }
    }

    private static void CommitOutput(PreparedOutput output)
    {
        if (output.AllowsReplacingExistingFile && File.Exists(output.FinalPath))
        {
            File.Replace(output.TemporaryPath, output.FinalPath, null);
            return;
        }

        if (File.Exists(output.FinalPath))
        {
            throw new CompressionException("输出文件已存在，未覆盖原文件。");
        }

        File.Move(output.TemporaryPath, output.FinalPath);
    }

    private static string BuildArguments(CompressionTask task, string temporaryPath)
    {
        return task.Engine switch
        {
            EngineKind.Oxipng => "-o 2 --out " + Quote(temporaryPath) + " " + Quote(task.SourcePath),
            EngineKind.Pngquant => "--quality=65-80 --speed 4 --skip-if-larger --output " + Quote(temporaryPath) + " -- " + Quote(task.SourcePath),
            EngineKind.MozJpeg => "--quality 75 --output " + Quote(temporaryPath) + " --preserve-metadata " + Quote(task.SourcePath),
            _ => throw new ArgumentOutOfRangeException(nameof(task.Engine))
        };
    }

    private static string Quote(string value)
    {
        if (value == null)
        {
            throw new ArgumentNullException(nameof(value));
        }

        var trailingBackslashes = 0;
        var quoted = new System.Text.StringBuilder("\"");
        foreach (var character in value)
        {
            if (character == '\\')
            {
                trailingBackslashes++;
                quoted.Append(character);
            }
            else if (character == '\"')
            {
                quoted.Append('\\', trailingBackslashes + 1);
                quoted.Append(character);
                trailingBackslashes = 0;
            }
            else
            {
                trailingBackslashes = 0;
                quoted.Append(character);
            }
        }

        quoted.Append('\\', trailingBackslashes);
        quoted.Append('\"');
        return quoted.ToString();
    }

    private void DeleteIfPresent(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                _deleteFile(path);
            }
        }
        catch
        {
            // Cleanup cannot hide the compression failure or stop the serial queue.
        }
    }

    private void NotifyTaskFailed(CompressionTask task)
    {
        try
        {
            _onTaskFailed?.Invoke(task);
        }
        catch
        {
            // Observers are diagnostic only and must not alter queue progress.
        }
    }

    private void NotifyTaskStarted(CompressionTask task)
    {
        try
        {
            _onTaskStarted?.Invoke(task);
        }
        catch
        {
            // Observers are diagnostic only and must not alter queue progress.
        }
    }

    private static string FailureReason(Exception exception) =>
        exception is CompressionException ? exception.Message : "无法完成本次压缩。";
}
