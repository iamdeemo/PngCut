# PngCut Windows 版 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 交付可在 Windows 7 SP1、Windows 10 和 Windows 11 离线运行的 PngCut x86/x64 免安装客户端，保持现有交互逻辑。

**Architecture:** 新建独立 windows/ 解决方案。PngCut.Core 管理发现、输出、任务和统计快照；PngCut.Engine 管理随包二进制和串行队列；PngCut.Desktop 是 WPF 壳层和 Win11 风格主题。Windows 7 使用同一程序，只降级阴影与透明增强。

**Tech Stack:** C#、WPF、.NET Framework 4.8、NUnit 3、FlaUI UIA3、MSBuild、PowerShell、oxipng、pngquant、MozJPEG。

---

## 文件结构

~~~text
windows/
  PngCut.sln
  README.md
  build/Build-Zip.ps1
  build/Test-ReleaseLayout.ps1
  build/Detect-DotNet48.ps1
  src/PngCut.Core/{Models,Services}/
  src/PngCut.Engine/
  src/PngCut.Desktop/{Controls,Themes,Resources}/
  PngCut.Tests/
  tests/manual/CompatibilityChecklist.md
~~~

### Task 1: 创建核心模型和完成态统计快照

**Files:**
- Create: windows/PngCut.sln
- Create: windows/src/PngCut.Core/PngCut.Core.csproj
- Create: windows/src/PngCut.Core/Models/CompressionTask.cs
- Create: windows/src/PngCut.Core/Models/ImageFormat.cs
- Create: windows/src/PngCut.Core/Models/CompressionMode.cs
- Create: windows/src/PngCut.Core/Models/OutputMode.cs
- Create: windows/PngCut.Tests/PngCut.Tests.csproj
- Create: windows/PngCut.Tests/CompressionTaskTests.cs

- [ ] **Step 1: 写失败测试。**

~~~csharp
[Test]
public void Complete_freezes_byte_counts()
{
    var task = new CompressionTask(@"C:\in\photo.png", ImageFormat.Png,
        CompressionMode.Lossless, EngineKind.Oxipng);
    task.Complete(@"C:\out\photo_pngcut.png", 200, 80);

    Assert.That(task.State, Is.EqualTo(TaskState.Completed));
    Assert.That(task.OriginalBytes, Is.EqualTo(200));
    Assert.That(task.CompressedBytes, Is.EqualTo(80));
    Assert.That(task.SavingsPercent, Is.EqualTo(60));
}
~~~

- [ ] **Step 2: 运行并确认类型缺失。**

Run: cd windows; msbuild PngCut.sln /t:Restore,Build /p:Configuration=Debug; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 编译失败，提示 CompressionTask、ImageFormat、CompressionMode、EngineKind 不存在。

- [ ] **Step 3: 创建最小实现。**

~~~xml
<Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup><TargetFrameworkVersion>v4.8</TargetFrameworkVersion><OutputType>Library</OutputType><LangVersion>latest</LangVersion></PropertyGroup>
  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
</Project>
~~~

~~~csharp
public sealed class CompressionTask
{
    public CompressionTask(string sourcePath, ImageFormat format, CompressionMode displayMode, EngineKind engine)
    { SourcePath = sourcePath; Format = format; DisplayMode = displayMode; Engine = engine; State = TaskState.Queued; }

    public string SourcePath { get; }
    public ImageFormat Format { get; }
    public CompressionMode DisplayMode { get; }
    public EngineKind Engine { get; }
    public TaskState State { get; private set; }
    public long? OriginalBytes { get; private set; }
    public long? CompressedBytes { get; private set; }
    public string OutputPath { get; private set; }
    public int SavingsPercent => OriginalBytes > 0 && CompressedBytes.HasValue
        ? (int)Math.Max(0, Math.Round((OriginalBytes.Value - CompressedBytes.Value) * 100d / OriginalBytes.Value)) : 0;
    public void Complete(string outputPath, long originalBytes, long compressedBytes)
    { OutputPath = outputPath; OriginalBytes = originalBytes; CompressedBytes = compressedBytes; State = TaskState.Completed; }
}
~~~

Define ImageFormat.Png/Jpeg, CompressionMode.Lossless/Balanced, OutputMode.Adjacent/Custom/Overwrite, TaskState.Queued/Processing/Completed/Failed, and EngineKind.Oxipng/Pngquant/MozJpeg.

- [ ] **Step 4: 重新运行测试。**

Run: cd windows; msbuild PngCut.sln /t:Restore,Build /p:Configuration=Debug; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: Complete_freezes_byte_counts passes.

- [ ] **Step 5: 提交。**

~~~bash
git add windows/PngCut.sln windows/src/PngCut.Core windows/PngCut.Tests
git commit -m "feat(windows): add core task model"
~~~

### Task 2: 实现发现、输出策略与引擎选择

**Files:**
- Create: windows/src/PngCut.Core/Services/FileDiscovery.cs
- Create: windows/src/PngCut.Core/Services/OutputPolicy.cs
- Modify: windows/src/PngCut.Core/Models/CompressionTask.cs
- Create: windows/PngCut.Tests/FileDiscoveryTests.cs
- Create: windows/PngCut.Tests/OutputPolicyTests.cs

- [ ] **Step 1: 写失败测试。**

~~~csharp
[Test]
public void Folder_import_keeps_relative_filename()
{
    var path = OutputPolicy.ForFolderImport(@"D:\art\project", @"D:\art\project\icons\logo.JPG");
    Assert.That(path, Is.EqualTo(@"D:\art\project_pngcut\icons\logo.JPG"));
}

[TestCase("PHOTO.JPG", ImageFormat.Jpeg, EngineKind.MozJpeg, CompressionMode.Balanced)]
[TestCase("icon.png", ImageFormat.Png, EngineKind.Oxipng, CompressionMode.Lossless)]
public void Discovery_routes_supported_images(string name, ImageFormat format, EngineKind engine, CompressionMode mode)
{
    var task = FileDiscovery.CreateTask(@"D:\in\" + name, CompressionMode.Lossless);
    Assert.That(task.Format, Is.EqualTo(format));
    Assert.That(task.Engine, Is.EqualTo(engine));
    Assert.That(task.DisplayMode, Is.EqualTo(mode));
}
~~~

- [ ] **Step 2: 运行并确认服务缺失。**

Run: cd windows; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 编译失败，提示 FileDiscovery 和 OutputPolicy 未定义。

- [ ] **Step 3: 实现大小写不敏感的发现与确定性输出。**

~~~csharp
public static CompressionTask CreateTask(string path, CompressionMode pngMode)
{
    var extension = Path.GetExtension(path).ToLowerInvariant();
    if (extension == ".png")
        return new CompressionTask(path, ImageFormat.Png, pngMode,
            pngMode == CompressionMode.Lossless ? EngineKind.Oxipng : EngineKind.Pngquant);
    if (extension == ".jpg" || extension == ".jpeg")
        return new CompressionTask(path, ImageFormat.Jpeg, CompressionMode.Balanced, EngineKind.MozJpeg);
    return null;
}

public static string ForSingleFile(string sourcePath) =>
    Path.Combine(Path.GetDirectoryName(sourcePath),
        Path.GetFileNameWithoutExtension(sourcePath) + "_pngcut" + Path.GetExtension(sourcePath));
~~~

For a folder import, use the path relative to selected root under a sibling root named <root>_pngcut. Reserve destination collisions with -2, -3 before the extension. Count non-image regular files as skipped.

Add an OutputMode OutputMode property to CompressionTask, defaulted to OutputMode.Adjacent in its constructor; OutputPolicy uses it to select adjacent, custom, or overwrite destinations.

- [ ] **Step 4: 运行测试。**

Run: cd windows; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 支持格式、单图片后缀、嵌套文件夹、碰撞命名和非图片计数测试通过。

- [ ] **Step 5: 提交。**

~~~bash
git add windows/src/PngCut.Core windows/PngCut.Tests/FileDiscoveryTests.cs windows/PngCut.Tests/OutputPolicyTests.cs
git commit -m "feat(windows): add discovery and output policies"
~~~

### Task 3: 实现本地引擎与安全串行队列

**Files:**
- Create: windows/src/PngCut.Engine/PngCut.Engine.csproj
- Create: windows/src/PngCut.Engine/CompressionOutcome.cs
- Create: windows/src/PngCut.Engine/EngineResolver.cs
- Create: windows/src/PngCut.Engine/ProcessRunner.cs
- Create: windows/src/PngCut.Engine/CompressionQueue.cs
- Create: windows/PngCut.Tests/CompressionQueueTests.cs
- Create: windows/PngCut.Tests/EngineResolverTests.cs

- [ ] **Step 1: 写失败测试。**

~~~csharp
[Test]
public void Resolver_uses_x86_subdirectory_for_32_bit_process()
{
    var resolver = new EngineResolver(@"C:\PngCut\engines", false);
    Assert.That(resolver.Resolve(EngineKind.Pngquant), Is.EqualTo(@"C:\PngCut\engines\x86\pngquant.exe"));
}

[Test]
public async Task No_change_does_not_replace_source_when_overwrite_is_selected()
{
    var task = NewPngTask(OutputMode.Overwrite);
    var queue = new CompressionQueue(new FakeRunner(CompressionOutcome.NoChange));
    await queue.EnqueueAsync(task);
    await queue.WaitForIdleAsync();

    Assert.That(task.OutputPath, Is.EqualTo(task.SourcePath));
    Assert.That(task.State, Is.EqualTo(TaskState.Completed));
}

private static CompressionTask NewPngTask(OutputMode mode) =>
    new CompressionTask(@"C:\\in\\source.png", ImageFormat.Png, CompressionMode.Balanced,
        EngineKind.Pngquant, mode);

private sealed class FakeRunner : IProcessRunner
{
    private readonly CompressionOutcome _outcome;
    public FakeRunner(CompressionOutcome outcome) { _outcome = outcome; }
    public Task<ProcessResult> RunAsync(string fileName, string arguments) =>
        Task.FromResult(new ProcessResult(_outcome == CompressionOutcome.NoChange ? 98 : 0, "", ""));
}
~~~

- [ ] **Step 2: 运行并确认 Engine 类型缺失。**

Run: cd windows; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 编译失败，提示 EngineResolver、CompressionQueue、CompressionOutcome 未定义。

- [ ] **Step 3: 实现进程执行与安全提交。**

~~~csharp
public enum CompressionOutcome { Compressed, NoChange }

public interface IProcessRunner
{
    Task<ProcessResult> RunAsync(string fileName, string arguments);
}

public sealed class ProcessResult
{
    public ProcessResult(int exitCode, string standardOutput, string standardError)
    { ExitCode = exitCode; StandardOutput = standardOutput; StandardError = standardError; }
    public int ExitCode { get; }
    public string StandardOutput { get; }
    public string StandardError { get; }
}

public async Task<CompressionOutcome> RunAsync(CompressionTask task, string temporaryPath)
{
    var result = await _runner.RunAsync(_resolver.Resolve(task.Engine), BuildArguments(task, temporaryPath));
    if (task.Engine == EngineKind.Pngquant && (result.ExitCode == 98 || result.ExitCode == 99))
        return CompressionOutcome.NoChange;
    if (result.ExitCode != 0) throw new CompressionException(result.StandardError);
    if (!File.Exists(temporaryPath) || new FileInfo(temporaryPath).Length == 0)
        throw new CompressionException("压缩程序没有生成有效输出文件。");
    return CompressionOutcome.Compressed;
}
~~~

For every task create a unique sibling temporary file. Run one task at a time. Validate before File.Replace or File.Move, then call task.Complete with source and final byte counts. For NoChange, remove temporary output, do not replace the source, and use source length for both snapshot values. Store Chinese failure reason and continue to the next task. Use pngquant arguments --quality=65-80 --speed 4 --skip-if-larger.

- [ ] **Step 4: 运行测试。**

Run: cd windows; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 串行、失败后继续、重试、98/99、覆盖保护、完成统计冻结测试通过。

- [ ] **Step 5: 提交。**

~~~bash
git add windows/src/PngCut.Engine windows/PngCut.Tests/CompressionQueueTests.cs windows/PngCut.Tests/EngineResolverTests.cs
git commit -m "feat(windows): add offline compression queue"
~~~

### Task 4: 实现设置保存和 Windows 7 运行环境提示

**Files:**
- Create: windows/src/PngCut.Core/Models/AppSettings.cs
- Create: windows/src/PngCut.Core/Services/SettingsStore.cs
- Create: windows/PngCut.Tests/SettingsStoreTests.cs
- Create: windows/build/Detect-DotNet48.ps1

- [ ] **Step 1: 写失败测试。**

~~~csharp
[Test]
public void Store_round_trips_mode_and_output_policy()
{
    var path = Path.Combine(TestContext.CurrentContext.WorkDirectory, "settings.json");
    var store = new SettingsStore(path);
    store.Save(new AppSettings { PngMode = CompressionMode.Balanced,
        OutputMode = OutputMode.Custom, CustomOutputDirectory = @"D:\out" });

    var restored = store.Load();
    Assert.That(restored.PngMode, Is.EqualTo(CompressionMode.Balanced));
    Assert.That(restored.CustomOutputDirectory, Is.EqualTo(@"D:\out"));
}
~~~

- [ ] **Step 2: 运行并确认 SettingsStore 缺失。**

Run: cd windows; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 编译失败，提示 SettingsStore 未定义。

- [ ] **Step 3: 实现 JSON 设置与运行环境检查。**

SettingsStore 原子写入 %AppData%\PngCut\settings.json。读取不到或 JSON 无效时返回 Lossless + Adjacent 默认值，且不删除用户文件。

~~~powershell
$release = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
if ($release -ge 528040) { exit 0 }
Write-Output 'PngCut 需要 Microsoft .NET Framework 4.8。请安装后重新打开程序。'
exit 1
~~~

App.xaml.cs 仅在 Windows 7 运行检查；失败时显示中文 MessageBox、打开微软官方安装页后退出。Windows 10/11 直接启动。

- [ ] **Step 4: 运行测试与脚本。**

Run: cd windows; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll; powershell -NoProfile -ExecutionPolicy Bypass -File build\Detect-DotNet48.ps1

Expected: 设置测试通过；已安装 .NET 4.8 的测试机脚本返回 0。

- [ ] **Step 5: 提交。**

~~~bash
git add windows/src/PngCut.Core/Models/AppSettings.cs windows/src/PngCut.Core/Services/SettingsStore.cs windows/PngCut.Tests/SettingsStoreTests.cs windows/build/Detect-DotNet48.ps1
git commit -m "feat(windows): persist settings and detect runtime"
~~~

### Task 5: 构建 WPF Win11 风格界面

**Files:**
- Create: windows/src/PngCut.Desktop/PngCut.Desktop.csproj
- Create: windows/src/PngCut.Desktop/App.xaml
- Create: windows/src/PngCut.Desktop/App.xaml.cs
- Create: windows/src/PngCut.Desktop/MainWindow.xaml
- Create: windows/src/PngCut.Desktop/MainWindow.xaml.cs
- Create: windows/src/PngCut.Desktop/ViewModels/MainViewModel.cs
- Create: windows/src/PngCut.Desktop/ViewModels/TaskRowViewModel.cs
- Create: windows/src/PngCut.Desktop/Controls/ModeSelector.xaml
- Create: windows/src/PngCut.Desktop/Controls/ModeSelector.xaml.cs
- Create: windows/src/PngCut.Desktop/Themes/Colors.xaml
- Create: windows/src/PngCut.Desktop/Themes/Controls.xaml
- Create: windows/src/PngCut.Desktop/Resources/AppIcon.ico

- [ ] **Step 1: 写 UI 自动化冒烟测试。**

~~~csharp
[Test]
public void Main_window_exposes_drop_target_mode_buttons_and_settings()
{
    using (var app = LaunchPngCut())
    {
        Assert.That(app.Find("DropTarget").Bounds.Width, Is.GreaterThan(300));
        Assert.That(app.Find("LosslessMode").Bounds.Height, Is.GreaterThanOrEqualTo(44));
        Assert.That(app.Find("BalancedMode").Bounds.Height, Is.GreaterThanOrEqualTo(44));
        Assert.That(app.Find("SettingsButton").Bounds.Width, Is.GreaterThanOrEqualTo(44));
    }
}

private static FlaUI.Core.Application LaunchPngCut() =>
    FlaUI.Core.Application.Launch(Path.Combine(TestContext.CurrentContext.TestDirectory, "PngCut.exe"));
~~~

Use FlaUI UIA3 in the net48 test project.

- [ ] **Step 2: 运行 UI 测试，确认 PngCut.exe 不存在。**

Run: cd windows; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 启动失败，提示 PngCut.exe 不存在。

- [ ] **Step 3: 实现主题、窗口、抽屉和绑定。**

Colors.xaml 定义 Accent=#2482F1、Workspace=#F4F4F4、Drawer=#FCFCFC。主按钮、切换器和抽屉使用相同资源。

ModeSelector 使用蓝色圆角 Border 表示选中态；两个标签在滑块到位前保持深色。使用 160ms CubicEase(EaseOut) 平移，避免文字先变白闪烁。

~~~xml
<Window MinWidth="720" MinHeight="520" Background="{StaticResource WorkspaceBrush}">
  <Grid>
    <Grid x:Name="Workspace" AutomationProperties.AutomationId="DropTarget" />
    <local:ModeSelector x:Name="ModeSelector" />
    <Button AutomationProperties.AutomationId="SettingsButton" MinWidth="44" MinHeight="44" />
    <Border x:Name="SettingsScrim" Visibility="Collapsed" />
    <Border x:Name="SettingsDrawer" Background="{StaticResource DrawerBrush}" />
  </Grid>
</Window>
~~~

The drawer uses TranslateTransform over the same 160ms curve, remains above workspace while closing, and scrim click closes it. Bind MainViewModel to FileDiscovery, CompressionQueue and SettingsStore. Native file dialog uses Chinese labels: 图片文件|*.png;*.jpg;*.jpeg.

- [ ] **Step 4: 运行 UI 和单元测试。**

Run: cd windows; msbuild PngCut.sln /t:Build /p:Configuration=Debug; vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: UI smoke test and all Core/Engine tests pass.

- [ ] **Step 5: 提交。**

~~~bash
git add windows/src/PngCut.Desktop windows/PngCut.Tests
git commit -m "feat(windows): add native desktop interface"
~~~

### Task 6: 添加两种架构引擎、ICO 和真实集成测试

**Files:**
- Create: windows/src/PngCut.Desktop/Resources/engines/x86/{oxipng,pngquant,mozjpeg-helper}.exe
- Create: windows/src/PngCut.Desktop/Resources/engines/x64/{oxipng,pngquant,mozjpeg-helper}.exe
- Create: windows/src/PngCut.Desktop/Resources/AppIcon.ico
- Create: windows/PngCut.Tests/RealEngineIntegrationTests.cs
- Modify: windows/src/PngCut.Desktop/PngCut.Desktop.csproj
- Modify: windows/README.md

- [ ] **Step 1: 写真实引擎 opt-in 测试。**

~~~csharp
[Test]
public async Task Real_pngquant_no_change_keeps_the_source_size()
{
    Assume.That(Environment.GetEnvironmentVariable("PNGCUT_RUN_REAL_ENGINES"), Is.EqualTo("1"));
    var task = CreateAlreadyOptimizedPngTask();
    await _queue.EnqueueAsync(task);
    await _queue.WaitForIdleAsync();

    Assert.That(task.State, Is.EqualTo(TaskState.Completed));
    Assert.That(task.OriginalBytes, Is.EqualTo(task.CompressedBytes));
}
~~~

- [ ] **Step 2: 启用测试，确认引擎缺失时明确失败。**

Run: set PNGCUT_RUN_REAL_ENGINES=1 && cd windows && vstest.console.exe PngCut.Tests\bin\Debug\PngCut.Tests.dll

Expected: 报告缺失引擎路径，不得显示成功。

- [ ] **Step 3: 构建可复核的固定版本资源。**

Use oxipng 10.2.0、pngquant 3.0.3、MozJPEG 4.1.5。将每个上游归档 SHA-256 写到 windows/README.md；为 x86/x64 分别构建；用 dumpbin /headers 验证架构。将现有 SVG 转换为 16/20/24/32/48/256 px ICO，并在 csproj 设置 ApplicationIcon。

- [ ] **Step 4: 复制资源并运行真实测试。**

~~~xml
<Content Include="Resources\engines\**\*.exe"><CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory></Content>
<Content Include="Resources\AppIcon.ico"><CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory></Content>
~~~

Run: set PNGCUT_RUN_REAL_ENGINES=1 && cd windows && vstest.console.exe PngCut.Tests\bin\Release\PngCut.Tests.dll

Expected: PNG 无损、PNG 平衡、JPG/JPEG 成功；已优化 PNG 以 0% 完成，不显示失败。

- [ ] **Step 5: 提交。**

~~~bash
git add windows/src/PngCut.Desktop/Resources windows/src/PngCut.Desktop/PngCut.Desktop.csproj windows/PngCut.Tests/RealEngineIntegrationTests.cs windows/README.md
git commit -m "feat(windows): bundle offline compression engines"
~~~

### Task 7: 制作免安装 ZIP 和发布校验

**Files:**
- Create: windows/build/Build-Zip.ps1
- Create: windows/build/Test-ReleaseLayout.ps1
- Create: windows/tests/manual/CompatibilityChecklist.md
- Modify: windows/README.md

- [ ] **Step 1: 写失败的 ZIP 布局检查。**

~~~powershell
param([string]$ZipPath)
$expanded = Join-Path $env:TEMP ("pngcut-release-" + [guid]::NewGuid())
Expand-Archive $ZipPath $expanded
if (-not (Test-Path (Join-Path $expanded 'PngCut.exe'))) { throw 'PngCut.exe missing' }
if (-not (Test-Path (Join-Path $expanded 'engines'))) { throw 'engine folder missing' }
if (Test-Path (Join-Path $expanded 'setup.exe')) { throw 'portable ZIP must not contain an installer' }
~~~

- [ ] **Step 2: 运行检查，确认 ZIP 不存在。**

Run: cd windows; powershell -NoProfile -ExecutionPolicy Bypass -File build\Test-ReleaseLayout.ps1 -ZipPath dist\PngCut-Windows-x64.zip

Expected: PngCut-Windows-x64.zip not found.

- [ ] **Step 3: 实现双架构 ZIP 构建。**

~~~powershell
param([ValidateSet('x86','x64')] [string]$Architecture)
$root = Split-Path -Parent $PSScriptRoot
$publish = Join-Path $root ("artifacts\" + $Architecture)
$stage = Join-Path $root ("dist\stage-" + $Architecture)
msbuild (Join-Path $root 'PngCut.sln') /t:Rebuild /p:Configuration=Release /p:Platform=$Architecture /p:OutDir="$publish\"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $stage | Out-Null
Copy-Item "$publish\PngCut.exe" $stage
Copy-Item "$publish\engines" $stage -Recurse
Copy-Item "$root\README.md" $stage
Compress-Archive -Path "$stage\*" -DestinationPath "$root\dist\PngCut-Windows-$Architecture.zip" -Force
~~~

Each ZIP contains only matching engine architecture, Chinese usage text, and required license/source notices. It contains no installer, API key, input picture, or settings file.

- [ ] **Step 4: 构建并校验。**

Run: cd windows; powershell -NoProfile -ExecutionPolicy Bypass -File build\Build-Zip.ps1 x86; powershell -NoProfile -ExecutionPolicy Bypass -File build\Build-Zip.ps1 x64; powershell -NoProfile -ExecutionPolicy Bypass -File build\Test-ReleaseLayout.ps1 -ZipPath dist\PngCut-Windows-x86.zip; powershell -NoProfile -ExecutionPolicy Bypass -File build\Test-ReleaseLayout.ps1 -ZipPath dist\PngCut-Windows-x64.zip

Expected: 两个 ZIP 都通过，且不包含安装器。

- [ ] **Step 5: 写兼容性清单并提交。**

CompatibilityChecklist.md 要列出 Windows 7 SP1、10、11 的 x86/x64 启动、拖放、文件选择、PNG 两档、JPG、文件夹输出、覆盖、失败后继续、删除输出后的冻结统计，以及 Win7 缺失 .NET 的中文提示。

~~~bash
git add windows/build windows/tests/manual windows/README.md
git commit -m "build(windows): add portable ZIP release"
~~~

## 最终验证

- [ ] 在 Windows 开发机或 Windows CI 执行 msbuild windows\PngCut.sln /t:Rebuild /p:Configuration=Release /p:Platform=x86 及 x64，二者成功。
- [ ] 运行全部 NUnit 与 FlaUI 测试，0 failures；设置 PNGCUT_RUN_REAL_ENGINES=1 后真实引擎测试通过。
- [ ] 运行 Build-Zip 和 Test-ReleaseLayout，两个 ZIP 均通过。
- [ ] 在 Windows 7 SP1、10、11 根据 CompatibilityChecklist 完成手动验证并记录系统、架构、结果和失败原因。
- [ ] 检查 ZIP 不含 API 密钥、源图片或用户设置，且应用不创建网络请求。
