using System;
using System.Collections.Generic;
using System.IO;
using PngCut.Core.Models;

namespace PngCut.Core.Services;

public sealed class PreparedOutput
{
    public PreparedOutput(string finalPath, string temporaryPath, bool allowsReplacingExistingFile)
    {
        FinalPath = finalPath ?? throw new ArgumentNullException(nameof(finalPath));
        TemporaryPath = temporaryPath ?? throw new ArgumentNullException(nameof(temporaryPath));
        AllowsReplacingExistingFile = allowsReplacingExistingFile;
    }

    public string FinalPath { get; }

    public string TemporaryPath { get; }

    public bool AllowsReplacingExistingFile { get; }
}

public static class OutputPolicy
{
    public static string ForSingleFile(string sourcePath)
    {
        if (sourcePath == null)
        {
            throw new ArgumentNullException(nameof(sourcePath));
        }

        return Path.Combine(
            DirectoryOf(sourcePath),
            Path.GetFileNameWithoutExtension(sourcePath) + "_pngcut" + Path.GetExtension(sourcePath).ToLowerInvariant());
    }

    public static string ForFolderImport(string selectedFolderRoot, string sourcePath)
    {
        if (selectedFolderRoot == null)
        {
            throw new ArgumentNullException(nameof(selectedFolderRoot));
        }
        if (sourcePath == null)
        {
            throw new ArgumentNullException(nameof(sourcePath));
        }

        var normalizedRoot = NormalizeSelectedFolderRoot(selectedFolderRoot);
        var outputRoot = OutputRootForFolderImport(normalizedRoot);
        var relativePath = RelativePath(normalizedRoot, sourcePath);
        return Path.Combine(outputRoot, relativePath);
    }

    public static PreparedOutput Prepare(
        string sourcePath,
        OutputMode outputMode,
        string? customDirectory = null,
        string? selectedFolderRoot = null,
        IEnumerable<string>? reservedFinalPaths = null)
    {
        if (sourcePath == null)
        {
            throw new ArgumentNullException(nameof(sourcePath));
        }

        string finalPath;
        var allowsReplacingExistingFile = outputMode == OutputMode.Overwrite;
        switch (outputMode)
        {
            case OutputMode.Adjacent:
                finalPath = selectedFolderRoot == null
                    ? ForSingleFile(sourcePath)
                    : ForFolderImport(selectedFolderRoot, sourcePath);
                finalPath = ReserveAvailable(finalPath, reservedFinalPaths);
                break;
            case OutputMode.Custom:
                var directory = ExistingCustomDirectory(customDirectory);
                finalPath = ReserveAvailable(
                    Path.Combine(directory, Path.GetFileName(ForSingleFile(sourcePath))),
                    reservedFinalPaths);
                break;
            case OutputMode.Overwrite:
                finalPath = sourcePath;
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(outputMode));
        }

        return new PreparedOutput(finalPath, TemporarySibling(finalPath), allowsReplacingExistingFile);
    }

    private static string ReserveAvailable(string initialPath, IEnumerable<string>? reservedFinalPaths)
    {
        var reserved = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (reservedFinalPaths != null)
        {
            foreach (var path in reservedFinalPaths)
            {
                if (!string.IsNullOrWhiteSpace(path))
                {
                    reserved.Add(path);
                }
            }
        }

        var directory = DirectoryOf(initialPath);
        var name = Path.GetFileNameWithoutExtension(initialPath);
        var extension = Path.GetExtension(initialPath);
        var suffix = 1;
        while (true)
        {
            var filename = suffix == 1 ? name + extension : name + "-" + suffix + extension;
            var candidate = Path.Combine(directory, filename);
            if (!reserved.Contains(candidate) && !File.Exists(candidate))
            {
                return candidate;
            }
            suffix++;
        }
    }

    private static string TemporarySibling(string finalPath)
    {
        var filename = Path.GetFileNameWithoutExtension(finalPath);
        var extension = Path.GetExtension(finalPath);
        return Path.Combine(
            DirectoryOf(finalPath),
            "." + filename + "." + Guid.NewGuid().ToString("N") + ".tmp" + extension);
    }

    private static string DirectoryOf(string path)
    {
        var directory = Path.GetDirectoryName(path);
        if (string.IsNullOrEmpty(directory))
        {
            throw new ArgumentException("The path must include a directory.", nameof(path));
        }

        return directory;
    }

    private static string ExistingCustomDirectory(string? customDirectory)
    {
        if (string.IsNullOrWhiteSpace(customDirectory) || !Directory.Exists(customDirectory))
        {
            throw new ArgumentException("The custom output directory must exist.", nameof(customDirectory));
        }

        return customDirectory;
    }

    private static string NormalizeSelectedFolderRoot(string path)
    {
        var fullPath = Path.GetFullPath(path);
        var pathRoot = Path.GetPathRoot(fullPath);
        if (string.IsNullOrEmpty(pathRoot))
        {
            throw new ArgumentException("The selected folder must have a rooted path.", nameof(path));
        }

        var normalized = fullPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var normalizedRoot = pathRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return string.IsNullOrEmpty(normalized) ||
               string.Equals(normalized, normalizedRoot, StringComparison.OrdinalIgnoreCase)
            ? pathRoot
            : normalized;
    }

    private static string OutputRootForFolderImport(string selectedFolderRoot)
    {
        var pathRoot = Path.GetPathRoot(selectedFolderRoot);
        if (string.Equals(selectedFolderRoot, pathRoot, StringComparison.OrdinalIgnoreCase))
        {
            return Path.Combine(pathRoot!, "_pngcut");
        }

        return Path.Combine(
            DirectoryOf(selectedFolderRoot),
            Path.GetFileName(selectedFolderRoot) + "_pngcut");
    }

    private static string RelativePath(string root, string path)
    {
        var canonicalRoot = NormalizeSelectedFolderRoot(root);
        var canonicalPath = Path.GetFullPath(path);
        var rootUri = new Uri(EnsureTrailingDirectorySeparator(canonicalRoot), UriKind.Absolute);
        var pathUri = new Uri(canonicalPath, UriKind.Absolute);
        if (!string.Equals(rootUri.Host, pathUri.Host, StringComparison.OrdinalIgnoreCase) ||
            !rootUri.IsBaseOf(pathUri))
        {
            throw new ArgumentException("The source path must be inside the selected folder.", nameof(path));
        }

        var relativeUri = rootUri.MakeRelativeUri(pathUri);
        var relativePath = Uri.UnescapeDataString(relativeUri.ToString())
            .Replace('/', Path.DirectorySeparatorChar);

        if (string.IsNullOrWhiteSpace(relativePath) ||
            Path.IsPathRooted(relativePath) ||
            relativePath.StartsWith(".." + Path.DirectorySeparatorChar, StringComparison.Ordinal) ||
            relativePath.StartsWith("../", StringComparison.Ordinal) ||
            relativePath.Equals("..", StringComparison.Ordinal))
        {
            throw new ArgumentException("The source path must be inside the selected folder.", nameof(path));
        }

        return relativePath;
    }

    private static string EnsureTrailingDirectorySeparator(string path) =>
        path.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal) ||
        path.EndsWith(Path.AltDirectorySeparatorChar.ToString(), StringComparison.Ordinal)
            ? path
            : path + Path.DirectorySeparatorChar;
}
