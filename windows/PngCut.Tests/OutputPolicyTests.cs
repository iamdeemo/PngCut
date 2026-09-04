using System;
using System.Collections.Generic;
using System.IO;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Core.Services;

namespace PngCut.Tests;

public class OutputPolicyTests
{
    [Test]
    public void ForSingleFile_adds_pngcut_suffix_and_normalizes_the_extension()
    {
        var path = OutputPolicy.ForSingleFile(@"D:\art\logo.JPG");

        Assert.That(path, Is.EqualTo(@"D:\art\logo_pngcut.jpg"));
    }

    [Test]
    public void ForFolderImport_keeps_relative_filename_under_sibling_pngcut_root()
    {
        var path = OutputPolicy.ForFolderImport(@"D:\art\project", @"D:\art\project\icons\logo.JPG");

        Assert.That(path, Is.EqualTo(@"D:\art\project_pngcut\icons\logo.JPG"));
    }

    [Test]
    public void ForFolderImport_keeps_an_image_at_the_selected_root()
    {
        var path = OutputPolicy.ForFolderImport(@"D:\art\project", @"D:\art\project\logo.JPG");

        Assert.That(path, Is.EqualTo(@"D:\art\project_pngcut\logo.JPG"));
    }

    [TestCase(@"D:\art\project\logo.JPG", @"D:\art\project_pngcut\logo.JPG")]
    [TestCase(@"D:\art\project\icons\logo.JPG", @"D:\art\project_pngcut\icons\logo.JPG")]
    public void ForFolderImport_normalizes_a_trailing_selected_root_separator(string source, string expected)
    {
        var path = OutputPolicy.ForFolderImport(@"D:\art\project\", source);

        Assert.That(path, Is.EqualTo(expected));
    }

    [Test]
    public void ForFolderImport_uses_a_safe_pngcut_directory_for_a_drive_root()
    {
        var path = OutputPolicy.ForFolderImport(@"D:\", @"D:\art\logo.JPG");

        Assert.That(path, Is.EqualTo(@"D:\_pngcut\art\logo.JPG"));
    }

    [Test]
    public void ForFolderImport_uses_a_safe_pngcut_directory_for_a_unc_share_root()
    {
        var path = OutputPolicy.ForFolderImport(@"\\server\share\", @"\\server\share\icons\logo.JPG");

        Assert.That(path, Is.EqualTo(@"\\server\share\_pngcut\icons\logo.JPG"));
    }

    [Test]
    public void ForFolderImport_keeps_nested_paths_on_the_same_unc_server()
    {
        var path = OutputPolicy.ForFolderImport(
            @"\\server\share\project",
            @"\\server\share\project\icons\logo.JPG");

        Assert.That(path, Is.EqualTo(@"\\server\share\project_pngcut\icons\logo.JPG"));
    }

    [Test]
    public void ForFolderImport_rejects_a_source_on_another_unc_server()
    {
        Assert.That(
            () => OutputPolicy.ForFolderImport(
                @"\\server-a\share\project",
                @"\\server-b\share\project\logo.JPG"),
            Throws.TypeOf<ArgumentException>());
    }

    [Test]
    public void Prepare_adjacent_uses_single_file_destination_without_creating_an_output()
    {
        var source = Path.Combine(Path.GetTempPath(), "PngCut-OutputPolicy", "banner.png");
        var prepared = OutputPolicy.Prepare(source, OutputMode.Adjacent);

        Assert.That(prepared.FinalPath, Is.EqualTo(Path.Combine(Path.GetDirectoryName(source)!, "banner_pngcut.png")));
        Assert.That(File.Exists(prepared.FinalPath), Is.False);
        Assert.That(Directory.Exists(Path.GetDirectoryName(prepared.FinalPath)!), Is.False);
    }

    [Test]
    public void Prepare_custom_rejects_a_missing_directory()
    {
        var root = Path.Combine(Path.GetTempPath(), "PngCut-OutputPolicy-" + Guid.NewGuid());
        Assert.That(
            () => OutputPolicy.Prepare(Path.Combine(root, "banner.png"), OutputMode.Custom, Path.Combine(root, "custom")),
            Throws.TypeOf<ArgumentException>());
    }

    [Test]
    public void Prepare_custom_uses_an_existing_directory()
    {
        var directory = Path.Combine(Path.GetTempPath(), "PngCut-OutputPolicy-" + Guid.NewGuid());
        Directory.CreateDirectory(directory);
        try
        {
            var prepared = OutputPolicy.Prepare(Path.Combine(directory, "logo.JPG"), OutputMode.Custom, directory);

            Assert.That(prepared.FinalPath, Is.EqualTo(Path.Combine(directory, "logo_pngcut.jpg")));
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Test]
    public void Prepare_overwrite_keeps_source_as_final_and_uses_a_distinct_temporary_sibling()
    {
        var prepared = OutputPolicy.Prepare(@"D:\art\logo.JPG", OutputMode.Overwrite);

        Assert.That(prepared.FinalPath, Is.EqualTo(@"D:\art\logo.JPG"));
        Assert.That(prepared.TemporaryPath, Is.Not.EqualTo(prepared.FinalPath));
        Assert.That(Path.GetDirectoryName(prepared.TemporaryPath), Is.EqualTo(@"D:\art"));
        Assert.That(prepared.AllowsReplacingExistingFile, Is.True);
    }

    [Test]
    public void Prepare_reserves_case_insensitive_collisions_with_incrementing_suffixes()
    {
        var existing = new[] { @"D:\out\LOGO_PNGCUT.jpg" };
        var second = OutputPolicy.Prepare(@"D:\out\logo.JPG", OutputMode.Adjacent, reservedFinalPaths: existing);
        var third = OutputPolicy.Prepare(
            @"D:\out\logo.JPG",
            OutputMode.Adjacent,
            reservedFinalPaths: new[] { existing[0], second.FinalPath });

        Assert.That(second.FinalPath, Is.EqualTo(@"D:\out\logo_pngcut-2.jpg"));
        Assert.That(third.FinalPath, Is.EqualTo(@"D:\out\logo_pngcut-3.jpg"));
    }

    [Test]
    public void Prepare_uses_a_numbered_name_when_an_adjacent_output_already_exists()
    {
        var directory = Path.Combine(Path.GetTempPath(), "PngCut-OutputPolicy-" + Guid.NewGuid());
        Directory.CreateDirectory(directory);
        try
        {
            var source = Path.Combine(directory, "logo.png");
            var existing = Path.Combine(directory, "logo_pngcut.png");
            File.WriteAllText(source, "source");
            File.WriteAllText(existing, "existing");

            var prepared = OutputPolicy.Prepare(source, OutputMode.Adjacent);

            Assert.That(prepared.FinalPath, Is.EqualTo(Path.Combine(directory, "logo_pngcut-2.png")));
            Assert.That(File.ReadAllText(existing), Is.EqualTo("existing"));
            Assert.That(File.Exists(prepared.FinalPath), Is.False);
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Test]
    public void Prepare_custom_reserves_case_insensitive_collisions()
    {
        var directory = Path.Combine(Path.GetTempPath(), "PngCut-OutputPolicy-" + Guid.NewGuid());
        Directory.CreateDirectory(directory);
        try
        {
            var prepared = OutputPolicy.Prepare(
                Path.Combine(directory, "logo.JPG"),
                OutputMode.Custom,
                customDirectory: directory,
                reservedFinalPaths: new[] { Path.Combine(directory, "LOGO_PNGCUT.jpg") });

            Assert.That(prepared.FinalPath, Is.EqualTo(Path.Combine(directory, "logo_pngcut-2.jpg")));
        }
        finally
        {
            Directory.Delete(directory, true);
        }
    }

    [Test]
    public void Prepare_folder_import_preserves_relative_original_names()
    {
        var prepared = OutputPolicy.Prepare(
            @"D:\art\project\icons\logo.JPG",
            OutputMode.Adjacent,
            selectedFolderRoot: @"D:\art\project");

        Assert.That(prepared.FinalPath, Is.EqualTo(@"D:\art\project_pngcut\icons\logo.JPG"));
    }
}
