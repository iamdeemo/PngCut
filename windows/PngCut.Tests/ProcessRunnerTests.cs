using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using NUnit.Framework;
using PngCut.Engine;

namespace PngCut.Tests;

[TestFixture]
[Platform("Win")]
public class ProcessRunnerTests
{
    private string _directory = null!;

    [SetUp]
    public void SetUp()
    {
        _directory = Path.Combine(Path.GetTempPath(), "PngCut-ProcessRunner-" + Guid.NewGuid().ToString("N"));
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
    public async Task RunAsync_captures_exit_output_error_and_passes_shell_metacharacters_as_one_literal_argument()
    {
        var fixture = Path.Combine(_directory, "capture.ps1");
        File.WriteAllText(fixture, @"
param([string]$Value)
[Console]::Out.WriteLine('OUT:' + $Value)
[Console]::Error.WriteLine('ERR:' + $Value)
exit 37
", new UTF8Encoding(false));
        var literal = "text & | < > ^ ;";
        var runner = new ProcessRunner();

        var result = await runner.RunAsync(
            Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
            "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(fixture) + " -Value " + Quote(literal));

        Assert.That(result.ExitCode, Is.EqualTo(37));
        Assert.That(result.StandardOutput.Trim(), Is.EqualTo("OUT:" + literal));
        Assert.That(result.StandardError.Trim(), Is.EqualTo("ERR:" + literal));
    }

    private static string Quote(string value) => "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
}
