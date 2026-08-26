using System;
using System.Collections.Concurrent;
using System.IO;
using System.Runtime.Serialization.Json;
using System.Text;
using PngCut.Core.Models;

namespace PngCut.Core.Services;

public interface ISettingsFileSystem
{
    bool FileExists(string path);

    void CreateDirectory(string path);

    string ReadAllText(string path);

    void WriteAllText(string path, string contents);

    void ReplaceFile(string sourcePath, string destinationPath);

    void MoveFile(string sourcePath, string destinationPath);

    void DeleteFile(string path);
}

public sealed class SettingsStore
{
    private static readonly ConcurrentDictionary<string, object> FileLocks =
        new(StringComparer.OrdinalIgnoreCase);

    private readonly ISettingsFileSystem _fileSystem;
    private readonly object _fileLock;

    public SettingsStore(string? settingsPath = null, ISettingsFileSystem? fileSystem = null)
    {
        SettingsPath = Path.GetFullPath(settingsPath ?? DefaultPath);
        _fileSystem = fileSystem ?? new SettingsFileSystem();
        _fileLock = FileLocks.GetOrAdd(SettingsPath, _ => new object());
    }

    public static string DefaultPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "PngCut",
        "settings.json");

    public string SettingsPath { get; }

    public AppSettings Load()
    {
        lock (_fileLock)
        {
            try
            {
                if (!_fileSystem.FileExists(SettingsPath))
                {
                    return DefaultSettings();
                }

                var settings = Deserialize(_fileSystem.ReadAllText(SettingsPath));
                return IsValid(settings) ? settings! : DefaultSettings();
            }
            catch (Exception exception) when (
                exception is IOException ||
                exception is UnauthorizedAccessException ||
                exception is InvalidOperationException ||
                exception is System.Runtime.Serialization.SerializationException)
            {
                return DefaultSettings();
            }
        }
    }

    public void Save(AppSettings settings)
    {
        if (settings == null)
        {
            throw new ArgumentNullException(nameof(settings));
        }

        lock (_fileLock)
        {
            var directory = Path.GetDirectoryName(SettingsPath)!;
            var temporaryPath = Path.Combine(directory, "." + Path.GetFileName(SettingsPath) + "." + Guid.NewGuid() + ".tmp");
            try
            {
                var serialized = Serialize(settings);
                _fileSystem.CreateDirectory(directory);
                _fileSystem.WriteAllText(temporaryPath, serialized);

                if (_fileSystem.FileExists(SettingsPath))
                {
                    _fileSystem.ReplaceFile(temporaryPath, SettingsPath);
                }
                else
                {
                    _fileSystem.MoveFile(temporaryPath, SettingsPath);
                }
            }
            catch
            {
                TryDelete(temporaryPath);
                throw;
            }
        }
    }

    private static AppSettings DefaultSettings() => new();

    private static bool IsValid(AppSettings? settings) =>
        settings != null &&
        Enum.IsDefined(typeof(CompressionMode), settings.PngMode) &&
        Enum.IsDefined(typeof(OutputMode), settings.OutputMode);

    private static string Serialize(AppSettings settings)
    {
        var serializer = new DataContractJsonSerializer(typeof(AppSettings));
        using var stream = new MemoryStream();
        serializer.WriteObject(stream, settings);
        return Encoding.UTF8.GetString(stream.ToArray());
    }

    private static AppSettings? Deserialize(string contents)
    {
        var serializer = new DataContractJsonSerializer(typeof(AppSettings));
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(contents));
        return serializer.ReadObject(stream) as AppSettings;
    }

    private void TryDelete(string path)
    {
        try
        {
            _fileSystem.DeleteFile(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private sealed class SettingsFileSystem : ISettingsFileSystem
    {
        public bool FileExists(string path) => File.Exists(path);

        public void CreateDirectory(string path) => Directory.CreateDirectory(path);

        public string ReadAllText(string path) => File.ReadAllText(path);

        public void WriteAllText(string path, string contents) => File.WriteAllText(path, contents);

        public void ReplaceFile(string sourcePath, string destinationPath) =>
            File.Replace(sourcePath, destinationPath, null);

        public void MoveFile(string sourcePath, string destinationPath) => File.Move(sourcePath, destinationPath);

        public void DeleteFile(string path)
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
    }
}
