using System;
using System.IO;
using PngCut.Core.Models;

namespace PngCut.Engine;

public sealed class EngineResolver
{
    private readonly string _engineRoot;
    private readonly bool _is64BitProcess;

    public EngineResolver(string? engineRoot = null, bool? is64BitProcess = null)
    {
        _engineRoot = engineRoot ?? Path.Combine(
            AppDomain.CurrentDomain.BaseDirectory,
            "Resources",
            "engines");
        _is64BitProcess = is64BitProcess ?? Environment.Is64BitProcess;
    }

    public string Resolve(EngineKind engine)
    {
        var executable = engine switch
        {
            EngineKind.Oxipng => "oxipng.exe",
            EngineKind.Pngquant => "pngquant.exe",
            EngineKind.MozJpeg => "mozjpeg-helper.exe",
            _ => throw new ArgumentOutOfRangeException(nameof(engine))
        };

        return Path.Combine(_engineRoot, _is64BitProcess ? "x64" : "x86", executable);
    }
}
