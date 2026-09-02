using System;
using PngCut.Core.Services;

namespace PngCut.Core.Models;

public sealed class CompressionTask
{
    public CompressionTask(
        string sourcePath,
        ImageFormat format,
        CompressionMode displayMode,
        EngineKind engine,
        OutputMode outputMode = OutputMode.Adjacent,
        string? customOutputDirectory = null,
        string? selectedFolderRoot = null)
    {
        SourcePath = sourcePath ?? throw new ArgumentNullException(nameof(sourcePath));
        Format = format;
        DisplayMode = displayMode;
        Engine = engine;
        OutputMode = outputMode;
        CustomOutputDirectory = customOutputDirectory;
        SelectedFolderRoot = selectedFolderRoot;
        State = TaskState.Queued;
    }

    public string SourcePath { get; }

    public ImageFormat Format { get; }

    public CompressionMode DisplayMode { get; }

    public EngineKind Engine { get; }

    public OutputMode OutputMode { get; }

    public string? CustomOutputDirectory { get; }

    public string? SelectedFolderRoot { get; }

    public TaskState State { get; private set; }

    public string? ErrorMessage { get; private set; }

    public FailureCode? ErrorCode { get; private set; }

    public long? OriginalBytes { get; private set; }

    public long? CompressedBytes { get; private set; }

    public string? OutputPath { get; private set; }

    public int SavingsPercent => OriginalBytes is > 0 && CompressedBytes.HasValue
        ? (int)Math.Max(0, Math.Round(
            (OriginalBytes.Value - CompressedBytes.Value) * 100d / OriginalBytes.Value))
        : 0;

    public void Complete(string outputPath, long originalBytes, long compressedBytes)
    {
        if (State == TaskState.Completed)
        {
            throw new InvalidOperationException("A completed task cannot be modified.");
        }

        if (originalBytes < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(originalBytes));
        }

        if (compressedBytes < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(compressedBytes));
        }

        OutputPath = outputPath ?? throw new ArgumentNullException(nameof(outputPath));
        OriginalBytes = originalBytes;
        CompressedBytes = compressedBytes;
        State = TaskState.Completed;
    }

    public void StartProcessing()
    {
        if (State != TaskState.Queued)
        {
            throw new InvalidOperationException("Only queued tasks can start processing.");
        }

        State = TaskState.Processing;
        ErrorMessage = null;
        ErrorCode = null;
    }

    public void Fail(FailureCode code)
    {
        if (State != TaskState.Processing)
        {
            throw new InvalidOperationException("Only processing tasks can fail.");
        }

        ErrorCode = code;
        ErrorMessage = FailureCatalog.Message(code);
        State = TaskState.Failed;
    }

    public void Retry()
    {
        if (State != TaskState.Failed)
        {
            throw new InvalidOperationException("Only failed tasks can be retried.");
        }

        ErrorMessage = null;
        ErrorCode = null;
        State = TaskState.Queued;
    }
}
