using System.Collections.Generic;
using System.IO;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Core.Services;
using PngCut.Desktop.ViewModels;

namespace PngCut.Tests;

public class FailureCatalogTests
{
    [Test]
    public void Failure_catalog_matches_the_shared_contract()
    {
        foreach (var entry in ErrorCatalog().Errors)
        {
            var code = System.Enum.Parse<FailureCode>(ToPascalCase(entry.Code));
            Assert.That(FailureCatalog.Message(code), Is.EqualTo(entry.Message));
        }
    }

    [Test]
    public void Engine_failure_presentation_does_not_expose_technical_details()
    {
        var task = new CompressionTask(
            @"C:\private\input.png",
            ImageFormat.Png,
            CompressionMode.Lossless,
            EngineKind.Oxipng);
        task.StartProcessing();
        task.Fail(FailureCode.EngineFailed);
        var message = new TaskRowViewModel(task, _ => System.Threading.Tasks.Task.CompletedTask).DetailText;

        Assert.That(message, Is.EqualTo("压缩程序执行失败。"));
        Assert.That(message, Does.Not.Contain(@"C:\private\input.png"));
        Assert.That(message, Does.Not.Contain("--unsafe-command"));
    }

    private static ErrorCatalogContract ErrorCatalog()
    {
        var path = Path.Combine(TestContext.CurrentContext.TestDirectory, "Contracts", "error-catalog.json");
        return new System.Web.Script.Serialization.JavaScriptSerializer()
            .Deserialize<ErrorCatalogContract>(File.ReadAllText(path));
    }

    private static string ToPascalCase(string code)
    {
        var result = new System.Text.StringBuilder();
        foreach (var segment in code.Split('_'))
        {
            result.Append(char.ToUpperInvariant(segment[0]));
            result.Append(segment.Substring(1));
        }
        return result.ToString();
    }

    private sealed class ErrorCatalogContract
    {
        public int Version { get; set; }
        public List<ErrorCatalogEntry> Errors { get; set; } = new();
    }

    private sealed class ErrorCatalogEntry
    {
        public string Code { get; set; } = null!;
        public string Message { get; set; } = null!;
    }
}
