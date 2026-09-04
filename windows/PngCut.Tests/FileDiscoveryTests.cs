using System;
using System.IO;
using System.Linq;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Core.Services;

namespace PngCut.Tests;

public class FileDiscoveryTests
{
    private string _directory = null!;

    [SetUp]
    public void SetUp()
    {
        _directory = Path.Combine(Path.GetTempPath(), "PngCut-FileDiscoveryTests-" + Guid.NewGuid());
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

    [TestCase("PHOTO.JPG", ImageFormat.Jpeg, EngineKind.MozJpeg, CompressionMode.Balanced)]
    [TestCase("scan.jPeG", ImageFormat.Jpeg, EngineKind.MozJpeg, CompressionMode.Balanced)]
    [TestCase("icon.png", ImageFormat.Png, EngineKind.Oxipng, CompressionMode.Lossless)]
    public void CreateTask_routes_supported_images_case_insensitively(
        string name,
        ImageFormat format,
        EngineKind engine,
        CompressionMode mode)
    {
        var task = FileDiscovery.CreateTask(@"D:\in\" + name, CompressionMode.Lossless);

        Assert.That(task, Is.Not.Null);
        Assert.That(task!.Format, Is.EqualTo(format));
        Assert.That(task.Engine, Is.EqualTo(engine));
        Assert.That(task.DisplayMode, Is.EqualTo(mode));
    }

    [Test]
    public void CreateTask_routes_balanced_png_to_pngquant()
    {
        var task = FileDiscovery.CreateTask(@"D:\in\icon.png", CompressionMode.Balanced);

        Assert.That(task, Is.Not.Null);
        Assert.That(task!.Format, Is.EqualTo(ImageFormat.Png));
        Assert.That(task.Engine, Is.EqualTo(EngineKind.Pngquant));
        Assert.That(task.DisplayMode, Is.EqualTo(CompressionMode.Balanced));
    }

    [Test]
    public void CreateTask_routes_jpeg_to_balanced_mozjpeg_regardless_of_png_mode()
    {
        var task = FileDiscovery.CreateTask(@"D:\in\photo.JPEG", CompressionMode.Balanced);

        Assert.That(task, Is.Not.Null);
        Assert.That(task!.Engine, Is.EqualTo(EngineKind.MozJpeg));
        Assert.That(task.DisplayMode, Is.EqualTo(CompressionMode.Balanced));
    }

    [Test]
    public void CreateTask_rejects_unsupported_extensions()
    {
        Assert.That(FileDiscovery.CreateTask(@"D:\in\notes.pdf", CompressionMode.Lossless), Is.Null);
    }

    [Test]
    public void Discover_recursively_returns_supported_tasks_and_counts_skipped_regular_files()
    {
        var nested = Path.Combine(_directory, "icons");
        Directory.CreateDirectory(nested);
        File.WriteAllText(Path.Combine(_directory, "banner.PNG"), "png");
        File.WriteAllText(Path.Combine(nested, "logo.JPG"), "jpeg");
        File.WriteAllText(Path.Combine(nested, "document.pdf"), "pdf");

        var result = FileDiscovery.Discover(new[] { _directory }, CompressionMode.Balanced);

        Assert.That(result.Tasks, Has.Count.EqualTo(2));
        Assert.That(result.Tasks.Any(task =>
            task.Format == ImageFormat.Png && task.Engine == EngineKind.Pngquant), Is.True);
        Assert.That(result.Tasks.Any(task =>
            task.Format == ImageFormat.Jpeg && task.Engine == EngineKind.MozJpeg &&
            task.DisplayMode == CompressionMode.Balanced), Is.True);
        Assert.That(result.SkippedRegularFileCount, Is.EqualTo(1));
    }

    [Test]
    public void CreateTask_captures_the_requested_output_mode()
    {
        var task = FileDiscovery.CreateTask(@"D:\in\icon.png", CompressionMode.Lossless, OutputMode.Custom);

        Assert.That(task, Is.Not.Null);
        Assert.That(task!.OutputMode, Is.EqualTo(OutputMode.Custom));
    }

    [Test]
    public void CreateTask_defaults_to_adjacent_output_mode()
    {
        var task = FileDiscovery.CreateTask(@"D:\in\icon.png", CompressionMode.Lossless);

        Assert.That(task, Is.Not.Null);
        Assert.That(task!.OutputMode, Is.EqualTo(OutputMode.Adjacent));
    }
}
