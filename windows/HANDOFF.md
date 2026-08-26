# PngCut Windows 版交接说明

更新时间：2026-08-22

## 2026-08-22 继续移植进度

已在本工作区继续完成 Windows 第 5 项的主要代码：

- 新增 `src/PngCut.Desktop` WPF 桌面项目并加入 `PngCut.sln`。
- 完成主窗口、图片/文件夹选择、拖放、任务列表、失败重试、输出位置设置和打开输出。
- 完成 Win11 风格颜色资源、44px 操作区、PNG 无损/平衡切换器及 160ms 设置抽屉动画。
- 增加 FlaUI UI 冒烟测试（`Explicit`，需要 Windows 桌面会话和已构建的 `PngCut.exe`）。
- 扩展任务携带自定义输出目录及文件夹导入根目录，队列现在能保留文件夹相对路径并在开始处理时通知 UI。
- 修复 `build/Detect-DotNet48.ps1` 的 Windows PowerShell 5.1 编码兼容性；脚本改为 ASCII 源码并仍输出中文提示。
- 安装并验证 Rust/Cargo、CMake、MSVC C++ Build Tools；固定构建 oxipng 10.2.0、pngquant 3.0.3、MozJPEG 4.1.5 的 x86/x64 引擎和 helper。
- 修复 MozJPEG Windows helper 的命令行参数；增加真实引擎集成测试、引擎许可证、应用图标、免安装 ZIP 构建和发布布局校验。
- 按 macOS SVG 资源对齐 Windows 图标，移除字符图标；补齐按钮 hover/pressed/focus/disabled 状态、44px 点击目标、自定义单选按钮和右侧设置抽屉动效，并修复输出/PNG 模式的 RadioButton 分组。
- 修复免安装 ZIP 的引擎目录：发布包现在保留运行时要求的 `Resources\engines\x86|x64` 布局；旧 ZIP 将引擎放在根目录，导致应用找不到压缩程序并显示通用失败信息。

已完成的本机验证：Debug/Release 的 Any CPU、x86、x64 构建均成功；x86 与 x64 的 NUnit 测试均为 60/60 通过；显式 FlaUI UI 冒烟测试通过；.NET 4.8 检测脚本返回 0。测试程序现在会主动关闭被测 `PngCut.exe`，不会锁住后续构建产物。

真实引擎集成测试已完成：x64 和 x86 均为 oxipng/pngquant/MozJPEG 3/3 通过。x86/x64 Release 免安装 ZIP 已生成并通过 `build/Test-ReleaseLayout.ps1`；发布说明、许可证和兼容性清单分别位于 `README.md`、`src/PngCut.Desktop/Resources/licenses` 和 `tests/manual/CompatibilityChecklist.md`。待完成事项主要是 Windows 7/10/11 实机手工兼容性验证，以及发布前确认引擎二进制的最终哈希和许可证材料。

## 本地位置

- macOS 原项目主目录：`/Users/jinpeng/Documents/ChatGPT/New project/FFPNG`
- Windows 版隔离工程：`/Users/jinpeng/Documents/ChatGPT/New project/FFPNG/.worktrees/windows-port`
- Windows 版 Git 分支：`feat/windows-port`

请在另一台电脑继续使用第二个目录。它是完整 Git 工作区，包含 macOS 项目、Windows 子工程、设计文档和实施计划。

## 已完成

Windows 子工程位于 `windows/`，已完成并提交以下部分：

1. **任务模型与统计快照**
   - `PngCut.Core` 与 NUnit 测试工程（目标 .NET Framework 4.8）。
   - PNG/JPG 类型、无损/平衡模式、输出策略、任务状态和压缩引擎枚举。
   - 压缩完成时冻结原始/压缩后字节数；删除输出文件后不应改变历史统计。
   - 已覆盖零字节、压缩变大、负数输入、重复完成写入等边界。

2. **文件发现与输出规则**
   - 递归识别 PNG/JPG/JPEG，统计跳过的非图片文件。
   - PNG 无损 → oxipng；PNG 平衡 → pngquant；JPG/JPEG → MozJPEG 平衡。
   - 单图片生成 `_pngcut` 后缀；文件夹导入生成同级 `<文件夹>_pngcut` 并保留内部目录与文件名。
   - 支持指定输出、覆盖原文件、大小写不敏感碰撞命名、磁盘根目录与 UNC 路径边界。

3. **本地压缩队列**
   - x86/x64 引擎路径解析、无 shell 外部进程启动、stdout/stderr 读取。
   - 串行执行、唯一临时文件、输出非空验证、失败后继续、失败重试、重复入队保护。
   - pngquant 退出码 98/99 视为“未变更”：不覆盖原文件，节省率为 0%。
   - 外部引擎原始错误不展示给用户；用户看到固定中文错误信息。
   - 输出路径预约在失败后释放；成功输出保留占用，防止误覆盖。

4. **设置和 Win7 前置检测**
   - 设置保存于 `%AppData%\\PngCut\\settings.json`，保存 PNG 模式及输出策略。
   - 无设置或无效 JSON 返回安全默认值，且不会删除/覆盖无效文件。
   - 原子写入和并发保存保护。
   - `windows/build/Detect-DotNet48.ps1` 检测 .NET Framework 4.8；缺失时输出中文提示。

## Windows 本机验证状态

当前开发机已安装 .NET SDK 8.0.424、Visual Studio Build Tools 2022/MSVC 14.44、CMake 4.4.2、Rust/Cargo 1.98.0，并已在 Windows PowerShell 中完成构建和测试：

- Debug/Release 的 Any CPU、x86、x64 构建均成功且无警告。
- x86 与 x64 的 NUnit 测试均为 60/60 通过；显式 FlaUI UI 冒烟测试通过。
- `PNGCUT_RUN_REAL_ENGINES=1` 下，x86/x64 的 oxipng、pngquant、MozJPEG 真实压缩测试均为 3/3 通过。
- x86/x64 免安装 ZIP 已生成，`build/Test-ReleaseLayout.ps1` 均通过。

## 未完成

实施计划在 `docs/superpowers/plans/2026-08-21-pngcut-windows-port.md`。

1. **发布前复核**：复核最终引擎哈希、许可证材料和发布说明。
2. **最终实机验证**：Windows 7 SP1、Windows 10、Windows 11；每个系统均覆盖 x86/x64、拖放、PNG 两档、JPG、文件夹输出、覆盖、失败重试和统计冻结。

## Windows 电脑准备

建议在 Windows 10/11 x64 上安装 Visual Studio Community：

- 工作负载：`.NET 桌面开发`
- 组件：`.NET Framework 4.8 SDK` 和 `.NET Framework 4.8 Targeting Pack`
- 另准备 Windows 7 SP1 x86 和 x64 虚拟机/实体机做最终兼容性验证，并安装 .NET Framework 4.8。

## 第一次构建

在 Windows PowerShell 中：

```powershell
cd 'C:\\path\\to\\windows-port\\windows'
dotnet restore .\\PngCut.sln -p:Platform=x64
dotnet build .\\PngCut.sln -c Debug -p:Platform=x64 --no-restore
dotnet test .\\PngCut.Tests\\PngCut.Tests.csproj -c Debug -p:Platform=x64 --no-build --no-restore
```

若使用 Visual Studio：打开 `windows\\PngCut.sln`，选择 `Debug | x64`，先运行所有 NUnit 测试。之后重复 `Debug | x86`。

## 关键提交记录

| 提交 | 内容 |
|---|---|
| `b3fb538`、`f7327f4` | 核心任务模型和统计快照边界 |
| `d8dcfde`、`56b32cd`、`b46b543` | 文件发现、输出策略、根目录与 UNC 路径保护 |
| `71bce8b`、`b23bb63`、`86616b0`、`79a71b7` | 本地压缩队列、失败处理、重试和并发安全 |
| `32b4214` | 设置持久化与 .NET 4.8 检测 |

## 注意事项

- 主目录当前有未提交的 macOS 项目改动；不要将其与 Windows 分支混合或执行 reset/checkout。
- Windows 版在 `feat/windows-port` 分支；完成后再决定合并策略。
- pngquant 的 GPL v3 要求发布 Windows ZIP 时保留许可证并提供对应源码与构建脚本。
