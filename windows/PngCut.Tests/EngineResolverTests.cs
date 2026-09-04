using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Engine;

namespace PngCut.Tests;

public class EngineResolverTests
{
    [TestCase(EngineKind.Oxipng, "oxipng.exe")]
    [TestCase(EngineKind.Pngquant, "pngquant.exe")]
    [TestCase(EngineKind.MozJpeg, "mozjpeg-helper.exe")]
    public void Resolver_uses_x86_subdirectory_for_32_bit_process(EngineKind engine, string executable)
    {
        var resolver = new EngineResolver(@"C:\PngCut\engines", false);

        Assert.That(resolver.Resolve(engine), Is.EqualTo(@"C:\PngCut\engines\x86\" + executable));
    }

    [Test]
    public void Resolver_uses_x64_subdirectory_for_64_bit_process()
    {
        var resolver = new EngineResolver(@"C:\PngCut\engines", true);

        Assert.That(resolver.Resolve(EngineKind.Pngquant), Is.EqualTo(@"C:\PngCut\engines\x64\pngquant.exe"));
    }
}
