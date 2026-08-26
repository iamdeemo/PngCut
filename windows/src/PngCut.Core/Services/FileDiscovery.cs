using System;
using System.Collections.Generic;
using System.IO;
using PngCut.Core.Models;

namespace PngCut.Core.Services;

public sealed class FileDiscoveryResult
{
    public FileDiscoveryResult(IReadOnlyList<CompressionTask> tasks, int skippedRegularFileCount)
    {
        Tasks = tasks ?? throw new ArgumentNullException(nameof(tasks));
        SkippedRegularFileCount = skippedRegularFileCount;
    }

    public IReadOnlyList<CompressionTask> Tasks { get; }

    public int SkippedRegularFileCount { get; }
}

public static class FileDiscovery
{
    public static CompressionTask? CreateTask(
        string path,
        CompressionMode pngMode,
        OutputMode outputMode = OutputMode.Adjacent,
        string? customOutputDirectory = null,
        string? selectedFolderRoot = null)
    {
        if (path == null)
        {
            throw new ArgumentNullException(nameof(path));
        }

        var extension = Path.GetExtension(path);
        if (extension.Equals(".png", StringComparison.OrdinalIgnoreCase))
        {
            var engine = pngMode == CompressionMode.Lossless ? EngineKind.Oxipng : EngineKind.Pngquant;
            return new CompressionTask(
                path,
                ImageFormat.Png,
                pngMode,
                engine,
                outputMode,
                customOutputDirectory,
                selectedFolderRoot);
        }

        if (extension.Equals(".jpg", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".jpeg", StringComparison.OrdinalIgnoreCase))
        {
            return new CompressionTask(
                path,
                ImageFormat.Jpeg,
                CompressionMode.Balanced,
                EngineKind.MozJpeg,
                outputMode,
                customOutputDirectory,
                selectedFolderRoot);
        }

        return null;
    }

    public static FileDiscoveryResult Discover(
        IEnumerable<string> inputPaths,
        CompressionMode pngMode,
        OutputMode outputMode = OutputMode.Adjacent,
        string? customOutputDirectory = null)
    {
        if (inputPaths == null)
        {
            throw new ArgumentNullException(nameof(inputPaths));
        }

        var tasks = new List<CompressionTask>();
        var seenPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var skippedRegularFileCount = 0;

        foreach (var inputPath in inputPaths)
        {
            if (string.IsNullOrWhiteSpace(inputPath))
            {
                continue;
            }

            if (File.Exists(inputPath))
            {
                Inspect(
                    inputPath,
                    pngMode,
                    outputMode,
                    customOutputDirectory,
                    null,
                    seenPaths,
                    tasks,
                    ref skippedRegularFileCount);
                continue;
            }

            if (!Directory.Exists(inputPath))
            {
                continue;
            }

            try
            {
                foreach (var path in Directory.EnumerateFiles(inputPath, "*", SearchOption.AllDirectories))
                {
                    Inspect(
                        path,
                        pngMode,
                        outputMode,
                        customOutputDirectory,
                        inputPath,
                        seenPaths,
                        tasks,
                        ref skippedRegularFileCount);
                }
            }
            catch (UnauthorizedAccessException)
            {
                // Keep importing the accessible part of a selected folder.
            }
            catch (IOException)
            {
                // A file can disappear while a folder is being enumerated.
            }
        }

        return new FileDiscoveryResult(tasks, skippedRegularFileCount);
    }

    private static void Inspect(
        string path,
        CompressionMode pngMode,
        OutputMode outputMode,
        string? customOutputDirectory,
        string? selectedFolderRoot,
        ISet<string> seenPaths,
        ICollection<CompressionTask> tasks,
        ref int skippedRegularFileCount)
    {
        var fullPath = Path.GetFullPath(path);
        if (!seenPaths.Add(fullPath))
        {
            return;
        }

        var task = CreateTask(
            fullPath,
            pngMode,
            outputMode,
            customOutputDirectory,
            selectedFolderRoot);
        if (task == null)
        {
            skippedRegularFileCount++;
            return;
        }

        tasks.Add(task);
    }
}
