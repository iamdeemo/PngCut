using System;
using System.Drawing;
using DrawingImageFormat = System.Drawing.Imaging.ImageFormat;
using System.IO;
using System.Threading.Tasks;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Engine;

namespace PngCut.Tests;

public class RealEngineIntegrationTests
{
    private string _directory = null!;

    [SetUp]
    public void SetUp()
    {
        Assume.That(
            Environment.GetEnvironmentVariable("PNGCUT_RUN_REAL_ENGINES"),
            Is.EqualTo("1"),
            "Set PNGCUT_RUN_REAL_ENGINES=1 to run the bundled engine integration tests.");

        _directory = Path.Combine(Path.GetTempPath(), "PngCut-RealEngines-" + Guid.NewGuid().ToString("N"));
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

    [TestCase(ImageFormat.Png, CompressionMode.Lossless, EngineKind.Oxipng, ".png")]
    [TestCase(ImageFormat.Png, CompressionMode.Balanced, EngineKind.Pngquant, ".png")]
    [TestCase(ImageFormat.Jpeg, CompressionMode.Balanced, EngineKind.MozJpeg, ".jpg")]
    public async Task Bundled_engine_completes_a_real_image(
        ImageFormat format,
        CompressionMode mode,
        EngineKind engine,
        string extension)
    {
        var source = Path.Combine(_directory, "source" + extension);
        CreateImage(source, format);
        var task = new CompressionTask(source, format, mode, engine);
        var engineRoot = Path.Combine(TestContext.CurrentContext.TestDirectory, "Resources", "engines");
        var executable = new EngineResolver(engineRoot).Resolve(engine);
        Assume.That(File.Exists(executable), Is.True, "Bundled engine is missing: " + executable);

        var queue = new CompressionQueue(resolver: new EngineResolver(engineRoot));
        await queue.EnqueueAsync(task);
        await queue.WaitForIdleAsync();

        Assert.That(task.State, Is.EqualTo(TaskState.Completed), task.ErrorMessage);
        Assert.That(task.OutputPath, Is.Not.Null);
        Assert.That(File.Exists(task.OutputPath!), Is.True);
        Assert.That(new FileInfo(task.OutputPath!).Length, Is.GreaterThan(0));
    }

    [Test]
    public async Task Bundled_oxipng_overwrites_a_real_source_image()
    {
        var source = Path.Combine(_directory, "overwrite-source.png");
        CreateImage(source, ImageFormat.Png);
        var engineRoot = Path.Combine(TestContext.CurrentContext.TestDirectory, "Resources", "engines");
        var task = new CompressionTask(
            source,
            ImageFormat.Png,
            CompressionMode.Lossless,
            EngineKind.Oxipng,
            OutputMode.Overwrite);
        var queue = new CompressionQueue(resolver: new EngineResolver(engineRoot));

        await queue.EnqueueAsync(task);
        await queue.WaitForIdleAsync();

        Assert.That(task.State, Is.EqualTo(TaskState.Completed), task.ErrorMessage);
        Assert.That(task.OutputPath, Is.EqualTo(source));
        Assert.That(new FileInfo(source).Length, Is.GreaterThan(0));
    }

    private static void CreateImage(string path, ImageFormat format)
    {
        using var bitmap = new Bitmap(24, 24);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.CornflowerBlue);
            graphics.FillEllipse(Brushes.White, 4, 4, 16, 16);
        }

        bitmap.Save(path, format == ImageFormat.Png ? DrawingImageFormat.Png : DrawingImageFormat.Jpeg);
    }
}
