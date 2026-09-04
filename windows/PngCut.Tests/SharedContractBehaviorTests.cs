using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Core.Services;

namespace PngCut.Tests;

public class SharedContractBehaviorTests
{
    private string _temporaryRoot = null!;

    [SetUp]
    public void SetUp()
    {
        _temporaryRoot = Path.Combine(Path.GetTempPath(), "PngCut-SharedContractBehaviorTests-" + Guid.NewGuid());
        Directory.CreateDirectory(_temporaryRoot);
    }

    [TearDown]
    public void TearDown()
    {
        if (Directory.Exists(_temporaryRoot))
        {
            Directory.Delete(_temporaryRoot, true);
        }
    }

    [Test]
    public void Adjacent_case_normalizes_the_output_extension()
    {
        var testCase = OutputCase("adjacent-normalizes-extension");
        var source = CreateFile(testCase.Source);

        var prepared = OutputPolicy.Prepare(source, OutputMode.Adjacent);

        Assert.That(Relative(prepared.FinalPath), Is.EqualTo(testCase.Expected));
    }

    [Test]
    public void Folder_case_preserves_the_relative_source_name()
    {
        var testCase = OutputCase("folder-preserves-relative-source-name");
        var source = CreateFile(testCase.Source);

        var prepared = OutputPolicy.Prepare(
            source,
            OutputMode.Adjacent,
            selectedFolderRoot: LogicalPath(testCase.SelectedFolder!));

        Assert.That(Relative(prepared.FinalPath), Is.EqualTo(testCase.Expected));
    }

    [Test]
    public void Adjacent_collision_uses_the_first_numbered_suffix()
    {
        var testCase = OutputCase("adjacent-collision-uses-two");
        var source = CreateFile(testCase.Source);
        foreach (var existingOutput in testCase.ExistingOutputs ?? new List<string>())
        {
            CreateFile(existingOutput);
        }

        var prepared = OutputPolicy.Prepare(source, OutputMode.Adjacent);

        Assert.That(Relative(prepared.FinalPath), Is.EqualTo(testCase.Expected));
    }

    [Test]
    public void Overwrite_case_keeps_the_source_and_allows_replacement()
    {
        var testCase = OutputCase("overwrite-keeps-source");
        var source = CreateFile(testCase.Source);

        var prepared = OutputPolicy.Prepare(source, OutputMode.Overwrite);

        Assert.That(Relative(prepared.FinalPath), Is.EqualTo(testCase.Expected));
        Assert.That(prepared.AllowsReplacingExistingFile, Is.True);
    }

    [Test]
    public void Custom_case_rejects_a_missing_directory_with_the_contract_code()
    {
        var testCase = OutputCase("custom-requires-existing-directory");
        var source = CreateFile(testCase.Source);

        Assert.That(
            () => OutputPolicy.Prepare(source, OutputMode.Custom, LogicalPath(testCase.CustomDirectory!)),
            Throws.TypeOf<ArgumentException>());
        Assert.That(testCase.ExpectedError, Is.EqualTo("output_policy_invalid"));
    }

    [Test]
    public void Windows_unc_share_root_case_matches_the_shared_contract()
    {
        var testCase = OutputCase("windows-unc-share-root");

        var finalPath = OutputPolicy.ForFolderImport(testCase.SelectedFolder!, testCase.Source);

        Assert.That(finalPath, Is.EqualTo(testCase.Expected));
    }

    [Test]
    public void Discovery_cases_match_the_shared_contract()
    {
        foreach (var testCase in DiscoveryContract().Cases.Where(testCase => testCase.Platforms.Contains("all")))
        {
            ResetTemporaryRoot();
            foreach (var path in testCase.Files)
            {
                CreateFile(path);
            }

            var result = FileDiscovery.Discover(
                testCase.SelectedPaths.Select(LogicalPath),
                CompressionMode.Lossless);

            Assert.That(
                result.Tasks.Select(task => Relative(task.SourcePath)).OrderBy(path => path),
                Is.EqualTo(testCase.ExpectedImages.OrderBy(path => path)),
                testCase.Id);
            Assert.That(result.SkippedRegularFileCount, Is.EqualTo(testCase.ExpectedSkippedRegularFiles), testCase.Id);
        }
    }

    private OutputPolicyContractCase OutputCase(string id) =>
        OutputPolicyContract().Cases.Single(testCase => testCase.Id == id);

    private OutputPolicyContract OutputPolicyContract() =>
        ReadContract<OutputPolicyContract>("output-policy-cases.json");

    private DiscoveryContract DiscoveryContract() =>
        ReadContract<DiscoveryContract>("discovery-cases.json");

    private static T ReadContract<T>(string name)
    {
        var json = File.ReadAllText(Path.Combine(TestContext.CurrentContext.TestDirectory, "Contracts", name));
        return new System.Web.Script.Serialization.JavaScriptSerializer().Deserialize<T>(json);
    }

    private string CreateFile(string logicalPath)
    {
        var path = LogicalPath(logicalPath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "fixture");
        return path;
    }

    private string LogicalPath(string logicalPath) =>
        Path.Combine(_temporaryRoot, logicalPath.Replace('/', Path.DirectorySeparatorChar));

    private void ResetTemporaryRoot()
    {
        Directory.Delete(_temporaryRoot, true);
        Directory.CreateDirectory(_temporaryRoot);
    }

    private string Relative(string path) =>
        path.Substring(_temporaryRoot.Length)
            .TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Replace(Path.DirectorySeparatorChar, '/');

    private sealed class OutputPolicyContract
    {
        public int Version { get; set; }
        public List<OutputPolicyContractCase> Cases { get; set; } = new();
    }

    private sealed class OutputPolicyContractCase
    {
        public string Id { get; set; } = null!;
        public List<string> Platforms { get; set; } = new();
        public string Policy { get; set; } = null!;
        public string Source { get; set; } = null!;
        public string? SelectedFolder { get; set; }
        public string? CustomDirectory { get; set; }
        public List<string>? ExistingOutputs { get; set; }
        public string? Expected { get; set; }
        public string? ExpectedError { get; set; }
    }

    private sealed class DiscoveryContract
    {
        public int Version { get; set; }
        public List<DiscoveryContractCase> Cases { get; set; } = new();
    }

    private sealed class DiscoveryContractCase
    {
        public string Id { get; set; } = null!;
        public List<string> Platforms { get; set; } = new();
        public List<string> SelectedPaths { get; set; } = new();
        public List<string> Files { get; set; } = new();
        public List<string> ExpectedImages { get; set; } = new();
        public int ExpectedSkippedRegularFiles { get; set; }
    }
}
