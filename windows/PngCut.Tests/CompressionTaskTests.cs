using System;
using NUnit.Framework;
using PngCut.Core.Models;

namespace PngCut.Tests;

public class CompressionTaskTests
{
    [Test]
    public void Complete_freezes_byte_counts()
    {
        var task = new CompressionTask(
            @"C:\in\photo.png",
            ImageFormat.Png,
            CompressionMode.Lossless,
            EngineKind.Oxipng);

        task.Complete(@"C:\out\photo_pngcut.png", 200, 80);

        Assert.That(task.State, Is.EqualTo(TaskState.Completed));
        Assert.That(task.OriginalBytes, Is.EqualTo(200));
        Assert.That(task.CompressedBytes, Is.EqualTo(80));
        Assert.That(task.SavingsPercent, Is.EqualTo(60));
    }

    [Test]
    public void Complete_cannot_overwrite_an_existing_snapshot()
    {
        var task = NewTask();
        task.Complete(@"C:\out\first.png", 200, 80);

        Assert.That(
            () => task.Complete(@"C:\out\second.png", 100, 50),
            Throws.TypeOf<InvalidOperationException>());
        Assert.That(task.OutputPath, Is.EqualTo(@"C:\out\first.png"));
        Assert.That(task.OriginalBytes, Is.EqualTo(200));
        Assert.That(task.CompressedBytes, Is.EqualTo(80));
    }

    [Test]
    public void Complete_returns_zero_savings_for_zero_source_bytes()
    {
        var task = NewTask();
        task.Complete(@"C:\out\photo_pngcut.png", 0, 0);

        Assert.That(task.SavingsPercent, Is.EqualTo(0));
    }

    [Test]
    public void Complete_returns_zero_savings_when_output_expands()
    {
        var task = NewTask();
        task.Complete(@"C:\out\photo_pngcut.png", 100, 120);

        Assert.That(task.SavingsPercent, Is.EqualTo(0));
    }

    [Test]
    public void Complete_rounds_savings_to_nearest_integer()
    {
        var task = NewTask();
        task.Complete(@"C:\out\photo_pngcut.png", 3, 2);

        Assert.That(task.SavingsPercent, Is.EqualTo(33));
    }

    [Test]
    public void Complete_rejects_negative_original_bytes()
    {
        var task = NewTask();

        Assert.That(
            () => task.Complete(@"C:\out\photo_pngcut.png", -1, 0),
            Throws.TypeOf<ArgumentOutOfRangeException>());
    }

    [Test]
    public void Complete_rejects_negative_compressed_bytes()
    {
        var task = NewTask();

        Assert.That(
            () => task.Complete(@"C:\out\photo_pngcut.png", 0, -1),
            Throws.TypeOf<ArgumentOutOfRangeException>());
    }

    [Test]
    public void Task_captures_output_context_for_folder_and_custom_imports()
    {
        var task = new CompressionTask(
            @"C:\in\icons\logo.png",
            ImageFormat.Png,
            CompressionMode.Lossless,
            EngineKind.Oxipng,
            OutputMode.Custom,
            @"C:\out",
            @"C:\in");

        Assert.That(task.CustomOutputDirectory, Is.EqualTo(@"C:\out"));
        Assert.That(task.SelectedFolderRoot, Is.EqualTo(@"C:\in"));
    }

    private static CompressionTask NewTask() => new(
        @"C:\in\photo.png",
        ImageFormat.Png,
        CompressionMode.Lossless,
        EngineKind.Oxipng);
}
