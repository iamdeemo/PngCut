using System;
using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media.Animation;
using Microsoft.Win32;
using PngCut.Core.Models;
using PngCut.Desktop.ViewModels;

namespace PngCut.Desktop;

public partial class MainWindow : Window
{
    private readonly MainViewModel _viewModel;
    private bool _updatingSettings;
    private int _drawerTransitionVersion;

    public MainWindow()
    {
        InitializeComponent();
        _viewModel = new MainViewModel();
        DataContext = _viewModel;
        _viewModel.PropertyChanged += ViewModel_OnPropertyChanged;
        Loaded += (_, _) =>
        {
            UpdateTaskState();
            UpdateSettingsControls();
        };
    }

    private void ChooseFilesButton_OnClick(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "选择图片文件",
            Filter = "图片文件|*.png;*.jpg;*.jpeg",
            Multiselect = true,
            CheckFileExists = true
        };
        if (dialog.ShowDialog(this) == true)
        {
            _viewModel.AddPaths(dialog.FileNames);
            UpdateTaskState();
        }
    }

    private void ChooseFolderButton_OnClick(object sender, RoutedEventArgs e)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "选择要处理的图片文件夹",
            ShowNewFolderButton = false
        };
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            _viewModel.AddPaths(new[] { dialog.SelectedPath });
            UpdateTaskState();
        }
    }

    private void ChooseOutputFolderButton_OnClick(object sender, RoutedEventArgs e)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "选择压缩后的图片保存位置",
            ShowNewFolderButton = true
        };
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            _viewModel.SetCustomOutputDirectory(dialog.SelectedPath);
            UpdateSettingsControls();
        }
    }

    private void RevealOutputButton_OnClick(object sender, RoutedEventArgs e) => _viewModel.RevealOutput();

    private void SettingsButton_OnClick(object sender, RoutedEventArgs e) =>
        _viewModel.IsSettingsOpen = !_viewModel.IsSettingsOpen;

    private void SettingsScrim_OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _viewModel.IsSettingsOpen = false;
    }

    private void CloseSettingsButton_OnClick(object sender, RoutedEventArgs e) =>
        _viewModel.IsSettingsOpen = false;

    private void OutputMode_OnClick(object sender, RoutedEventArgs e)
    {
        if (_updatingSettings || sender is not System.Windows.Controls.RadioButton radio)
        {
            return;
        }

        switch (radio.Tag as string)
        {
            case "Adjacent":
                _viewModel.SetOutputMode(OutputMode.Adjacent);
                break;
            case "Custom":
                if (!string.IsNullOrWhiteSpace(_viewModel.CustomOutputDirectory))
                {
                    _viewModel.SetOutputMode(OutputMode.Custom);
                }
                else
                {
                    ChooseOutputFolderButton_OnClick(sender, e);
                }
                break;
            case "Overwrite":
                _viewModel.SetOutputMode(OutputMode.Overwrite);
                break;
        }

        UpdateSettingsControls();
    }

    private void LosslessMode_OnClick(object sender, RoutedEventArgs e)
    {
        if (!_updatingSettings)
        {
            _viewModel.PngMode = CompressionMode.Lossless;
        }
        UpdateSettingsControls();
    }

    private void BalancedMode_OnClick(object sender, RoutedEventArgs e)
    {
        if (!_updatingSettings)
        {
            _viewModel.PngMode = CompressionMode.Balanced;
        }
        UpdateSettingsControls();
    }

    private void Window_OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop)
            ? DragDropEffects.Copy
            : DragDropEffects.None;
        e.Handled = true;
    }

    private void Window_OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] paths)
        {
            _viewModel.AddPaths(paths);
            UpdateTaskState();
        }

        e.Handled = true;
    }

    private void ViewModel_OnPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainViewModel.HasTasks) ||
            e.PropertyName == nameof(MainViewModel.SkippedRegularFileCount))
        {
            Dispatcher.BeginInvoke(new Action(UpdateTaskState));
        }
        else if (e.PropertyName == nameof(MainViewModel.IsSettingsOpen))
        {
            var isSettingsOpen = _viewModel.IsSettingsOpen;
            Dispatcher.BeginInvoke(new Action(() => UpdateDrawer(isSettingsOpen)));
        }
        else if (e.PropertyName == nameof(MainViewModel.OutputMode) ||
                 e.PropertyName == nameof(MainViewModel.CustomOutputDirectory) ||
                 e.PropertyName == nameof(MainViewModel.PngMode))
        {
            Dispatcher.BeginInvoke(new Action(UpdateSettingsControls));
        }
    }

    private void UpdateTaskState()
    {
        var hasTasks = _viewModel.HasTasks;
        EmptyState.Visibility = hasTasks ? Visibility.Collapsed : Visibility.Visible;
        TaskState.Visibility = hasTasks ? Visibility.Visible : Visibility.Collapsed;
        SkippedEmptyText.Text = _viewModel.SkippedRegularFileCount > 0
            ? _viewModel.SkippedRegularFileCount + " 个非图片文件未添加"
            : string.Empty;
    }

    private void UpdateSettingsControls()
    {
        _updatingSettings = true;
        try
        {
            AdjacentOutput.IsChecked = _viewModel.OutputMode == OutputMode.Adjacent;
            CustomOutput.IsChecked = _viewModel.OutputMode == OutputMode.Custom;
            OverwriteOutput.IsChecked = _viewModel.OutputMode == OutputMode.Overwrite;
            LosslessMode.IsChecked = _viewModel.PngMode == CompressionMode.Lossless;
            BalancedMode.IsChecked = _viewModel.PngMode == CompressionMode.Balanced;
        }
        finally
        {
            _updatingSettings = false;
        }
    }

    private void UpdateDrawer(bool isSettingsOpen)
    {
        var transitionVersion = ++_drawerTransitionVersion;
        var drawerWidth = Math.Max(SettingsDrawer.ActualWidth, SettingsDrawer.Width);
        var currentOffset = DrawerTransform.X;
        DrawerTransform.BeginAnimation(System.Windows.Media.TranslateTransform.XProperty, null);

        if (isSettingsOpen)
        {
            var startOffset = DrawerHost.Visibility == Visibility.Visible
                ? currentOffset
                : drawerWidth;
            DrawerHost.Visibility = Visibility.Visible;
            DrawerTransform.X = startOffset;
            var animation = new DoubleAnimation(startOffset, 0, TimeSpan.FromMilliseconds(200))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
            };
            DrawerTransform.BeginAnimation(System.Windows.Media.TranslateTransform.XProperty, animation);
            return;
        }

        if (DrawerHost.Visibility != Visibility.Visible)
        {
            return;
        }

        DrawerTransform.X = currentOffset;
        var close = new DoubleAnimation(currentOffset, drawerWidth, TimeSpan.FromMilliseconds(200))
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut }
        };
        close.Completed += (_, _) =>
        {
            if (transitionVersion == _drawerTransitionVersion && !_viewModel.IsSettingsOpen)
            {
                DrawerTransform.BeginAnimation(System.Windows.Media.TranslateTransform.XProperty, null);
                DrawerTransform.X = drawerWidth;
                DrawerHost.Visibility = Visibility.Collapsed;
            }
        };
        DrawerTransform.BeginAnimation(System.Windows.Media.TranslateTransform.XProperty, close);
    }
}
