namespace PngCut.Core.Models;

public sealed class AppSettings
{
    public CompressionMode PngMode { get; set; } = CompressionMode.Lossless;

    public OutputMode OutputMode { get; set; } = OutputMode.Adjacent;

    public string? CustomOutputDirectory { get; set; }
}
