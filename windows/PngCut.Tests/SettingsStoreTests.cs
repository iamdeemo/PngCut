using System;
using System.IO;
using System.Threading.Tasks;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Core.Services;

namespace PngCut.Tests;

public class SettingsStoreTests
{
    private string _directory = null!;

    [SetUp]
    public void SetUp()
    {
        _directory = Path.Combine(Path.GetTempPath(), "PngCut-SettingsStoreTests-" + Guid.NewGuid());
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
    public void Store_round_trips_png_mode_output_mode_and_custom_directory()
    {
        var path = Path.Combine(_directory, "settings.json");
        var store = new SettingsStore(path);

        store.Save(new AppSettings
        {
            PngMode = CompressionMode.Balanced,
            OutputMode = OutputMode.Custom,
            CustomOutputDirectory = @"D:\out"
        });

        var restored = store.Load();

        Assert.That(restored.PngMode, Is.EqualTo(CompressionMode.Balanced));
        Assert.That(restored.OutputMode, Is.EqualTo(OutputMode.Custom));
        Assert.That(restored.CustomOutputDirectory, Is.EqualTo(@"D:\out"));
    }

    [Test]
    public void Load_returns_default_settings_when_the_file_is_absent()
    {
        var store = new SettingsStore(Path.Combine(_directory, "missing.json"));

        var settings = store.Load();

        Assert.That(settings.PngMode, Is.EqualTo(CompressionMode.Lossless));
        Assert.That(settings.OutputMode, Is.EqualTo(OutputMode.Adjacent));
    }

    [Test]
    public void Load_returns_defaults_for_invalid_json_without_mutating_the_original_file()
    {
        var path = Path.Combine(_directory, "settings.json");
        const string invalidJson = "{ not valid json";
        File.WriteAllText(path, invalidJson);
        var store = new SettingsStore(path);

        var settings = store.Load();

        Assert.That(settings.PngMode, Is.EqualTo(CompressionMode.Lossless));
        Assert.That(settings.OutputMode, Is.EqualTo(OutputMode.Adjacent));
        Assert.That(File.ReadAllText(path), Is.EqualTo(invalidJson));
    }

    [Test]
    public void Default_path_is_under_the_current_users_appdata_directory()
    {
        var expected = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "PngCut",
            "settings.json");

        Assert.That(SettingsStore.DefaultPath, Is.EqualTo(expected));
    }

    [Test]
    public void Save_preserves_existing_settings_when_atomic_replace_fails()
    {
        var path = Path.Combine(_directory, "settings.json");
        var original = "{\"PngMode\":0,\"OutputMode\":0,\"CustomOutputDirectory\":null}";
        File.WriteAllText(path, original);
        var store = new SettingsStore(path, new ReplaceFailingFileSystem());

        Assert.That(
            () => store.Save(new AppSettings { PngMode = CompressionMode.Balanced }),
            Throws.TypeOf<IOException>());
        Assert.That(File.ReadAllText(path), Is.EqualTo(original));
    }

    [Test]
    public void Save_preserves_existing_settings_when_temporary_write_fails()
    {
        var path = Path.Combine(_directory, "settings.json");
        var original = "{\"PngMode\":0,\"OutputMode\":0,\"CustomOutputDirectory\":null}";
        File.WriteAllText(path, original);
        var store = new SettingsStore(path, new WriteFailingFileSystem());

        Assert.That(
            () => store.Save(new AppSettings { PngMode = CompressionMode.Balanced }),
            Throws.TypeOf<IOException>());
        Assert.That(File.ReadAllText(path), Is.EqualTo(original));
    }

    [Test]
    public void Concurrent_saves_leave_a_complete_json_document()
    {
        var path = Path.Combine(_directory, "settings.json");
        var store = new SettingsStore(path);
        var saves = new Task[20];

        for (var index = 0; index < saves.Length; index++)
        {
            var mode = index % 2 == 0 ? CompressionMode.Lossless : CompressionMode.Balanced;
            saves[index] = Task.Run(() => store.Save(new AppSettings { PngMode = mode }));
        }

        Task.WaitAll(saves);

        Assert.That(() => store.Load(), Throws.Nothing);
        Assert.That(File.ReadAllText(path), Does.StartWith("{"));
        Assert.That(File.ReadAllText(path), Does.EndWith("}"));
    }

    private sealed class ReplaceFailingFileSystem : ISettingsFileSystem
    {
        public bool FileExists(string path) => File.Exists(path);

        public void CreateDirectory(string path) => Directory.CreateDirectory(path);

        public string ReadAllText(string path) => File.ReadAllText(path);

        public void WriteAllText(string path, string contents) => File.WriteAllText(path, contents);

        public void ReplaceFile(string sourcePath, string destinationPath) =>
            throw new IOException("Replace failed.");

        public void MoveFile(string sourcePath, string destinationPath) => File.Move(sourcePath, destinationPath);

        public void DeleteFile(string path)
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
    }

    private sealed class WriteFailingFileSystem : ISettingsFileSystem
    {
        public bool FileExists(string path) => File.Exists(path);

        public void CreateDirectory(string path) => Directory.CreateDirectory(path);

        public string ReadAllText(string path) => File.ReadAllText(path);

        public void WriteAllText(string path, string contents) =>
            throw new IOException("Write failed.");

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
