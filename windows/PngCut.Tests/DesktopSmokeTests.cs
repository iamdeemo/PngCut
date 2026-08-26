using System;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using System.Windows.Media;
using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;
using NUnit.Framework;
using PngCut.Core.Models;
using PngCut.Desktop;
using PngCut.Desktop.Controls;
using PngCut.Desktop.ViewModels;
using WpfApplication = System.Windows.Application;
using WpfButton = System.Windows.Controls.Button;
using WpfGrid = System.Windows.Controls.Grid;

namespace PngCut.Tests;

public class DesktopSmokeTests
{
    [Test]
    [Explicit("Requires Windows WPF resource loading.")]
    [Apartment(ApartmentState.STA)]
    public void Mode_switch_animates_selection_and_text_foregrounds_together()
    {
        EnsureApplication();
        var selector = new ModeSelector();
        selector.ApplyTemplate();

        selector.SelectedMode = CompressionMode.Balanced;

        var selectionTransform = (TranslateTransform)selector.FindName("SelectionTransform");
        var losslessButton = (WpfButton)selector.FindName("LosslessMode");
        var balancedButton = (WpfButton)selector.FindName("BalancedMode");

        Assert.That(selectionTransform.HasAnimatedProperties, Is.True);
        Assert.That(((SolidColorBrush)losslessButton.Foreground).HasAnimatedProperties, Is.True);
        Assert.That(((SolidColorBrush)balancedButton.Foreground).HasAnimatedProperties, Is.True);
    }

    [Test]
    [Explicit("Requires a Windows WPF desktop session.")]
    [Apartment(ApartmentState.STA)]
    public void Repeated_settings_close_actions_collapse_the_drawer_host()
    {
        EnsureApplication();
        var window = new MainWindow();
        try
        {
            window.Show();
            var viewModel = (MainViewModel)window.DataContext;

            viewModel.IsSettingsOpen = true;
            PumpDispatcher(TimeSpan.FromMilliseconds(80));
            viewModel.IsSettingsOpen = false;
            PumpDispatcher(TimeSpan.FromMilliseconds(80));
            viewModel.IsSettingsOpen = true;
            PumpDispatcher(TimeSpan.FromMilliseconds(80));
            viewModel.IsSettingsOpen = false;
            PumpDispatcher(TimeSpan.FromMilliseconds(360));

            var drawerHost = (WpfGrid)window.FindName("DrawerHost");
            Assert.That(drawerHost.Visibility, Is.EqualTo(Visibility.Collapsed));
        }
        finally
        {
            window.Close();
        }
    }

    [Test]
    [Explicit("Requires a Windows desktop session and a built PngCut.exe.")]
    public void Main_window_exposes_drop_target_mode_buttons_and_settings()
    {
        var executable = Path.Combine(TestContext.CurrentContext.TestDirectory, "PngCut.exe");
        Assume.That(File.Exists(executable), Is.True, "Build the Desktop project before running the UI smoke test.");

        using var application = FlaUI.Core.Application.Launch(executable);
        using var automation = new UIA3Automation();
        try
        {
            var window = application.GetMainWindow(automation);

            Assert.That(window.FindFirstDescendant(cf => cf.ByAutomationId("DropTarget")), Is.Not.Null);
            Assert.That(window.FindFirstDescendant(cf => cf.ByAutomationId("LosslessMode")), Is.Not.Null);
            Assert.That(window.FindFirstDescendant(cf => cf.ByAutomationId("BalancedMode")), Is.Not.Null);
            var settingsButton = window.FindFirstDescendant(cf => cf.ByAutomationId("SettingsButton"))?.AsButton();
            Assert.That(settingsButton, Is.Not.Null);

            settingsButton!.Invoke();
            var closeButton = window.FindFirstDescendant(cf => cf.ByName("关闭"))?.AsButton();
            Assert.That(closeButton, Is.Not.Null);
            Assert.That(closeButton!.BoundingRectangle.Width, Is.LessThanOrEqualTo(100));
        }
        finally
        {
            try
            {
                application.Close();
            }
            catch
            {
                // The process may already have exited after a failed launch.
            }

            try
            {
                application.Kill();
            }
            catch
            {
                // Cleanup must not hide the UI assertion result.
            }
        }
    }

    private static void EnsureApplication()
    {
        var application = WpfApplication.Current ?? new WpfApplication();
        if (application.Resources.Contains("AccentBrush"))
        {
            return;
        }

        application.Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new System.Uri("/PngCut;component/Themes/Colors.xaml", System.UriKind.Relative)
        });
        application.Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new System.Uri("/PngCut;component/Themes/Icons.xaml", System.UriKind.Relative)
        });
        application.Resources.MergedDictionaries.Add(new ResourceDictionary
        {
            Source = new System.Uri("/PngCut;component/Themes/Controls.xaml", System.UriKind.Relative)
        });
    }

    private static void PumpDispatcher(TimeSpan duration)
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = duration
        };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            frame.Continue = false;
        };
        timer.Start();
        Dispatcher.PushFrame(frame);
    }
}
