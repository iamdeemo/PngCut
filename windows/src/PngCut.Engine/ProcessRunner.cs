using System;
using System.Diagnostics;
using System.Threading.Tasks;

namespace PngCut.Engine;

public interface IProcessRunner
{
    Task<ProcessResult> RunAsync(string fileName, string arguments);
}

public sealed class ProcessResult
{
    public ProcessResult(int exitCode, string standardOutput, string standardError)
    {
        ExitCode = exitCode;
        StandardOutput = standardOutput ?? string.Empty;
        StandardError = standardError ?? string.Empty;
    }

    public int ExitCode { get; }
    public string StandardOutput { get; }
    public string StandardError { get; }
}

public sealed class ProcessRunner : IProcessRunner
{
    public async Task<ProcessResult> RunAsync(string fileName, string arguments)
    {
        if (string.IsNullOrWhiteSpace(fileName))
        {
            throw new ArgumentException("An executable path is required.", nameof(fileName));
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments ?? string.Empty,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo };
        if (!process.Start())
        {
            throw new CompressionException("无法启动压缩程序。");
        }

        var standardOutput = process.StandardOutput.ReadToEndAsync();
        var standardError = process.StandardError.ReadToEndAsync();
        await Task.Run(() => process.WaitForExit()).ConfigureAwait(false);
        return new ProcessResult(process.ExitCode, await standardOutput.ConfigureAwait(false),
            await standardError.ConfigureAwait(false));
    }
}
