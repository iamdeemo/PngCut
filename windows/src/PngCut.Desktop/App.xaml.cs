using System;
using System.Diagnostics;
using System.Windows;
using Microsoft.Win32;

namespace PngCut.Desktop;

public partial class App : Application
{
    private const int NetFramework48Release = 528040;
    private const string NetFrameworkDownloadUrl =
        "https://dotnet.microsoft.com/download/dotnet-framework/net48";

    protected override void OnStartup(StartupEventArgs e)
    {
        if (IsWindows7() && !HasNetFramework48())
        {
            MessageBox.Show(
                "PngCut 需要 Microsoft .NET Framework 4.8。请安装后重新打开程序。",
                "PngCut",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            OpenDownloadPage();
            Shutdown(1);
            return;
        }

        base.OnStartup(e);
    }

    private static bool IsWindows7()
    {
        var version = Environment.OSVersion.Version;
        return version.Major == 6 && version.Minor == 1;
    }

    private static bool HasNetFramework48()
    {
        using var key = RegistryKey.OpenBaseKey(
            RegistryHive.LocalMachine,
            Environment.Is64BitOperatingSystem ? RegistryView.Registry64 : RegistryView.Registry32)
            .OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full");
        var release = key?.GetValue("Release");
        return release is int value && value >= NetFramework48Release;
    }

    private static void OpenDownloadPage()
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = NetFrameworkDownloadUrl,
                UseShellExecute = true
            });
        }
        catch
        {
            // The runtime prompt remains useful even when a browser cannot be started.
        }
    }
}
