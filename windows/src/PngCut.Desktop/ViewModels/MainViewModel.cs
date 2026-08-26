using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using PngCut.Core.Models;
using PngCut.Core.Services;
using PngCut.Engine;

namespace PngCut.Desktop.ViewModels;

public sealed class MainViewModel : INotifyPropertyChanged
{
    private readonly SettingsStore _settingsStore;
    private readonly CompressionQueue _queue;
    private readonly Action<Action> _dispatch;
    private AppSettings _settings;
    private int _skippedRegularFileCount;
    private bool _isSettingsOpen;

    public MainViewModel(
        SettingsStore? settingsStore = null,
        CompressionQueue? queue = null,
        Action<Action>? dispatch = null)
    {
        _settingsStore = settingsStore ?? new SettingsStore();
        _settings = _settingsStore.Load();
        if (_settings.OutputMode == OutputMode.Custom &&
            (string.IsNullOrWhiteSpace(_settings.CustomOutputDirectory) ||
             !Directory.Exists(_settings.CustomOutputDirectory)))
        {
            _settings.OutputMode = OutputMode.Adjacent;
            _settings.CustomOutputDirectory = null;
        }
        _dispatch = dispatch ?? DispatchOnApplicationThread;
        _queue = queue ?? new CompressionQueue(
            onTaskStarted: task => Dispatch(() => RefreshTask(task)),
            onTaskFailed: task => Dispatch(() => RefreshTask(task)));
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<TaskRowViewModel> Tasks { get; } = new();

    public CompressionMode PngMode
    {
        get => _settings.PngMode;
        set
        {
            if (_settings.PngMode == value)
            {
                return;
            }

            _settings.PngMode = value;
            SaveSettings();
            OnPropertyChanged();
        }
    }

    public OutputMode OutputMode
    {
        get => _settings.OutputMode;
        private set
        {
            if (_settings.OutputMode == value)
            {
                return;
            }

            _settings.OutputMode = value;
            SaveSettings();
            OnPropertyChanged();
            OnPropertyChanged(nameof(OutputModeLabel));
        }
    }

    public string? CustomOutputDirectory
    {
        get => _settings.CustomOutputDirectory;
        private set
        {
            if (string.Equals(_settings.CustomOutputDirectory, value, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            _settings.CustomOutputDirectory = value;
            SaveSettings();
            OnPropertyChanged();
        }
    }

    public string OutputModeLabel => OutputMode switch
    {
        OutputMode.Custom => "指定文件夹",
        OutputMode.Overwrite => "覆盖原文件",
        _ => "原文件旁边"
    };

    public int SkippedRegularFileCount
    {
        get => _skippedRegularFileCount;
        private set
        {
            if (_skippedRegularFileCount == value)
            {
                return;
            }

            _skippedRegularFileCount = value;
            OnPropertyChanged();
        }
    }

    public bool HasTasks => Tasks.Count > 0;

    public bool IsSettingsOpen
    {
        get => _isSettingsOpen;
        set
        {
            if (_isSettingsOpen == value)
            {
                return;
            }

            _isSettingsOpen = value;
            OnPropertyChanged();
        }
    }

    public bool CanRevealOutput => Tasks.Any(task => task.Model.State == TaskState.Completed);

    public void AddPaths(string[] paths)
    {
        if (paths == null || paths.Length == 0)
        {
            return;
        }

        var result = FileDiscovery.Discover(
            paths,
            PngMode,
            OutputMode,
            CustomOutputDirectory);
        SkippedRegularFileCount += result.SkippedRegularFileCount;

        foreach (var task in result.Tasks)
        {
            var row = new TaskRowViewModel(task, RetryTask);
            Tasks.Add(row);
            _ = ProcessTaskAsync(task);
        }

        OnPropertyChanged(nameof(HasTasks));
    }

    public void SetOutputMode(OutputMode mode)
    {
        if (mode == OutputMode.Custom && string.IsNullOrWhiteSpace(CustomOutputDirectory))
        {
            return;
        }

        OutputMode = mode;
    }

    public void SetCustomOutputDirectory(string directory)
    {
        if (string.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
        {
            return;
        }

        CustomOutputDirectory = Path.GetFullPath(directory);
        OutputMode = OutputMode.Custom;
    }

    public void RevealOutput()
    {
        var customDirectory = CustomOutputDirectory;
        if (OutputMode == OutputMode.Custom &&
            customDirectory is not null &&
            customDirectory.Length > 0)
        {
            OpenInExplorer(customDirectory);
            return;
        }

        var output = Tasks.LastOrDefault(task => task.Model.State == TaskState.Completed)?.Model.OutputPath;
        if (output is not null && output.Length > 0)
        {
            OpenInExplorer(output);
        }
    }

    private async Task ProcessTaskAsync(CompressionTask task)
    {
        try
        {
            await _queue.EnqueueAsync(task).ConfigureAwait(false);
        }
        catch
        {
            // Queue failures are represented on the task whenever processing has started.
        }

        Dispatch(() => RefreshTask(task));
    }

    private async Task RetryTask(TaskRowViewModel row)
    {
        try
        {
            await _queue.RetryAsync(row.Model).ConfigureAwait(false);
        }
        catch
        {
            // A duplicate click is harmless; the queue remains the source of truth.
        }

        Dispatch(() => RefreshTask(row.Model));
    }

    private void RefreshTask(CompressionTask task)
    {
        var row = Tasks.FirstOrDefault(item => ReferenceEquals(item.Model, task));
        row?.Refresh();
        OnPropertyChanged(nameof(CanRevealOutput));
    }

    private void SaveSettings()
    {
        try
        {
            _settingsStore.Save(_settings);
        }
        catch
        {
            // Settings are a convenience; a write failure must not interrupt an import.
        }
    }

    private void Dispatch(Action action) => _dispatch(action);

    private static void DispatchOnApplicationThread(Action action)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher == null || dispatcher.CheckAccess())
        {
            action();
            return;
        }

        dispatcher.BeginInvoke(action);
    }

    private static void OpenInExplorer(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = "/select,\"" + path + "\"",
                    UseShellExecute = true
                });
            }
            else if (Directory.Exists(path))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = path,
                    UseShellExecute = true
                });
            }
        }
        catch
        {
            // Revealing output is best effort and should not affect compression.
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class TaskRowViewModel : INotifyPropertyChanged
{
    private readonly Func<TaskRowViewModel, Task> _retry;

    public TaskRowViewModel(CompressionTask model, Func<TaskRowViewModel, Task> retry)
    {
        Model = model ?? throw new ArgumentNullException(nameof(model));
        _retry = retry ?? throw new ArgumentNullException(nameof(retry));
        RetryCommand = new RelayCommand(() => _ = _retry(this), () => CanRetry);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public CompressionTask Model { get; }

    public RelayCommand RetryCommand { get; }

    public string FileName => Path.GetFileName(Model.SourcePath);

    public string DetailText => Model.State switch
    {
        TaskState.Failed => Model.ErrorMessage ?? "压缩失败。",
        TaskState.Completed => FormatBytes(Model.OriginalBytes ?? 0) + " → " + FormatBytes(Model.CompressedBytes ?? 0),
        _ => FormatBytes(ReadSourceBytes())
    };

    public string StateText => Model.State switch
    {
        TaskState.Processing => "处理中",
        TaskState.Completed => "完成",
        TaskState.Failed => "失败",
        _ => "等待"
    };

    public string SavingsText => Model.State == TaskState.Completed
        ? "节省 " + Model.SavingsPercent + "%"
        : string.Empty;

    public bool IsProcessing => Model.State == TaskState.Processing;

    public bool CanRetry => Model.State == TaskState.Failed;

    public void Refresh()
    {
        OnPropertyChanged(nameof(DetailText));
        OnPropertyChanged(nameof(StateText));
        OnPropertyChanged(nameof(SavingsText));
        OnPropertyChanged(nameof(IsProcessing));
        OnPropertyChanged(nameof(CanRetry));
        RetryCommand.RaiseCanExecuteChanged();
    }

    private long ReadSourceBytes()
    {
        try
        {
            return new FileInfo(Model.SourcePath).Length;
        }
        catch
        {
            return 0;
        }
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes < 1024)
        {
            return bytes + " B";
        }

        if (bytes < 1024L * 1024)
        {
            return (bytes / 1024L) + " KB";
        }

        if (bytes < 1024L * 1024 * 1024)
        {
            return (bytes / (1024L * 1024)) + " MB";
        }

        return (bytes / (1024L * 1024 * 1024)) + " GB";
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}

public sealed class RelayCommand : System.Windows.Input.ICommand
{
    private readonly Action _execute;
    private readonly Func<bool>? _canExecute;

    public RelayCommand(Action execute, Func<bool>? canExecute = null)
    {
        _execute = execute ?? throw new ArgumentNullException(nameof(execute));
        _canExecute = canExecute;
    }

    public event EventHandler? CanExecuteChanged;

    public bool CanExecute(object? parameter) => _canExecute?.Invoke() ?? true;

    public void Execute(object? parameter) => _execute();

    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}
