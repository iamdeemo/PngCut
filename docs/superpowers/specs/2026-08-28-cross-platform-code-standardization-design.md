# PngCut 跨平台代码规范化设计

**状态：** 已确认，待实施
**范围：** GitHub `origin/main` 的 `macos/` 与 `windows/` 基线；本阶段不实现 GIF 功能。

## 背景与目标

PngCut 当前保留 SwiftUI/macOS 与 WPF/.NET Framework 4.8/Windows 两个原生客户端。两端支持的 PNG、JPG/JPEG 本地压缩业务大致相同，但逻辑以 Swift 和 C# 分别实现，测试与引擎版本信息分散在各自目录中。

本次规范化的目标不是将 macOS 迁移到 .NET 或将 Windows 迁移到 Swift，而是建立一个可版本化的跨语言行为契约，使两个原生实现持续遵守同一套输入、输出、队列和引擎规则。完成后，GIF 功能将在该契约上重新设计，避免先在某一平台形成不可复用的行为。

## 已保留的 GIF 文档

以下文件作为 GIF 功能的历史设计输入完整保留，不因本次目录调整删除或重写：

- `docs/superpowers/specs/2026-08-28-gif-compression-and-png-sequence-design.md`
- `docs/superpowers/plans/2026-08-28-gif-compression-and-png-sequence.md`

它们不代表本次标准化后的最终 GIF 实现计划。后续 GIF 设计必须以新的跨平台契约为准，并明确替换或修订其中与旧 `FFPNG/` 路径、旧任务模型不一致的部分。

## 方案选择

### 方案 A：共享行为契约与测试向量，保留原生实现（采用）

在仓库根目录新增 `shared/`，存放不依赖 Swift、C#、AppKit、WPF 或某一操作系统路径 API 的数据文件、规则说明和测试向量。macOS 与 Windows 保留各自的模型、队列、UI、进程调用和发布脚本，并各自读取/验证相同的向量。

优点是能够统一用户可感知的行为，同时不引入新运行时、不重写成熟的原生桌面 UI，也适合将来逐项加入 GIF 规则。缺点是共享物是契约数据而不是可直接编译的业务源码。

### 方案 B：提取新跨平台核心库

使用 Rust、C++ 或 .NET 重写文件发现、输出规划和队列，让 macOS/Windows 都调用同一二进制或 FFI 库。它能共享真正的可执行代码，但需要跨语言桥接、平台打包、调试和错误处理基础设施；现有稳定实现会被大规模替换。

本次不采用，因为它会将“规范现有行为”的任务扩大为一次跨平台重构。

### 方案 C：只统一目录和文档

维持两端现在的测试和业务逻辑，仅把资源移动到同名目录。它成本最低，但无法阻止输出碰撞、失败重试或引擎规则再次产生行为漂移。

本次不采用，因为它不能实现“公用代码放一起、规则保持一致”的目标。

## 目标目录与职责

```text
shared/
  contracts/v1/
    behavior.json              # 格式、模式、引擎、任务状态和不变式
    output-policy-cases.json   # 通用输出向量及标注平台归属的路径扩展向量
    discovery-cases.json       # 文件发现、大小写、递归、跳过与去重测试向量
    error-catalog.json         # 稳定错误码和简体中文用户文案
    engine-manifest.json       # 引擎版本、上游来源和许可证标识
  fixtures/
    README.md                  # 逻辑路径与每个平台临时目录映射规则

macos/
  PngCut/                      # SwiftUI、Foundation/AppKit、macOS 引擎与应用资源
  PngCutTests/                 # XCTest 契约适配器和 macOS 专属测试
  PngCutUITests/               # XCUITest，仅 macOS UI 行为
  scripts/                     # Bash、Xcode、DMG 检查

windows/
  src/                         # C# Core、Engine 与 WPF Desktop
  PngCut.Tests/                # NUnit 契约适配器和 Windows 专属测试
  build/                       # PowerShell、ZIP 检查
```

`shared/` 中不得放置平台二进制、Xcode/Visual Studio 工程文件、用户设置、真实用户图片或平台专属路径。引擎可执行文件仍分别留在 `macos/PngCut/Resources/` 与 `windows/src/PngCut.Desktop/Resources/`，因为 macOS 需要 arm64/x86_64 Mach-O，Windows 需要 x86/x64 `.exe`。

## 跨平台行为契约 v1

`behavior.json` 是唯一的语义来源；Swift 和 C# 枚举可使用本地命名，但必须映射到以下稳定值：

| 领域 | v1 契约 |
| --- | --- |
| 输入格式 | `png`、`jpeg`；扩展名大小写不敏感，JPEG 接受 `.jpg` 与 `.jpeg`。 |
| 压缩模式 | `lossless`、`balanced`；模式名称在 UI 中保持 `无损`、`平衡`。 |
| PNG 引擎 | 无损使用 `oxipng`；平衡使用 `pngquant`。 |
| JPEG 引擎 | 始终使用 `mozjpeg`，任务显示模式为 `balanced`。 |
| 任务状态 | `queued` → `processing` → `completed` 或 `failed`；只有 `failed` 任务可重试。 |
| 不变更 | pngquant 退出码 98/99 代表 `no_change`：删除临时文件，输出仍指向源文件，原始和结果字节数相等。 |
| 统计 | 任务完成后冻结原始字节数和结果字节数；之后删除输出也不得改变历史统计。 |
| 普通输出 | 同目录或自定义目录中的文件名为 `image_pngcut.png` 这一命名模式；输出扩展名规范为小写，碰撞后依次使用 `-2`、`-3`。 |
| 自定义输出 | 自定义输出目录必须已存在且是目录；不自动创建、也不接受普通文件路径。 |
| 文件夹输出 | 选中目录的同级目录使用 `folder_pngcut` 命名模式，内部相对路径保持不变；通用向量覆盖普通目录，卷根、UNC 等平台路径边界由标注的单平台扩展向量覆盖。 |
| 覆盖输出 | 仅 `overwrite` 可以替换源文件；其他策略碰到已存在或已预约的目标必须改名，不能覆盖。 |

引擎命令行参数仍属于平台适配器。契约只固定引擎身份、模式映射、无变更语义和输出结果；这样可以保留各平台必要的可执行文件解析和引号规则。

## 错误与用户文案

`error-catalog.json` 定义稳定错误码：`input_unreadable`、`output_policy_invalid`、`engine_unavailable`、`engine_failed`、`output_invalid` 与 `output_conflict`。每项带一条简体中文用户文案。

平台层捕获 Foundation、Process、`IOException`、`UnauthorizedAccessException` 等原始错误后转换为错误码；详细诊断只写入本地测试/开发日志，不直接展示源路径、命令行或系统异常。SwiftUI 与 WPF 都由同一错误码映射用户文案，避免当前 macOS 英文底层错误和 Windows 中文通用错误不一致。

## 测试向量与适配器

`shared/contracts/v1/*.json` 使用逻辑路径，例如 `/import/root/nested/Photo.PNG`，不直接保存 macOS 或 Windows 的绝对路径。各平台测试在临时目录创建等价文件树，再将逻辑路径转换为本机路径。

两个测试适配器必须逐项执行 `platforms` 包含其自身或为 `all` 的向量，并报告向量 ID。普通发现、输出、碰撞、覆盖、无变更和状态向量标记为 `all`；Windows 驱动器根与 UNC 向量只标记为 `windows`，macOS 卷根/标准化 URL 向量只标记为 `macos`。这样共享文件仍是唯一规则来源，但不会要求某一平台伪造另一平台的路径语义：

- macOS：`macos/PngCutTests/SharedContractTests.swift`，使用 `JSONDecoder`、`FileManager` 和 XCTest。
- Windows：`windows/PngCut.Tests/SharedContractTests.cs`，使用 .NET 内置 JSON 读取器、临时目录和 NUnit。

各自继续保留原有的队列并发、AppKit/WPF、Mach-O/EXE 解析、真实引擎和打包测试。共享向量不能模拟或替代这些平台专属测试。

## 引擎与许可证清单

`engine-manifest.json` 统一记录现有引擎：oxipng 10.2.0、pngquant 3.0.3、MozJPEG 4.1.5，以及上游项目、许可证标识和源代码/构建脚本位置。它不复制任何许可证全文；许可证仍随各平台发布包分发，以确保 DMG 和 ZIP 各自完整。

发布检查将验证两个平台声明的引擎版本与共享清单一致，同时保留 macOS 的 DMG 内容检查和 Windows 的 ZIP 布局检查。

## 实施顺序

1. 新增版本化共享契约、测试向量、引擎清单和说明；不改变当前 PNG/JPEG 用户行为。
2. 为 macOS 和 Windows 添加各自的契约读取测试，先暴露现有行为差异。
3. 逐个收敛发现、输出规划、队列状态、无变更、错误码和设置的行为；每次只修复一个契约向量导致的差异。
4. 更新两端 README、发布脚本和 CI，使共享契约校验成为 macOS DMG 与 Windows ZIP 发布前置条件。
5. 在 v1 通过两端测试后，基于同一结构另行设计 GIF 压缩和 PNG 序列转 GIF，并将新格式、序列规则、质量/FPS/循环和输出规则作为契约 v2 增量加入。

## 验收标准

- GitHub 最新 `origin/main` 的 `macos/` 与 `windows/` 都保留并能独立构建、测试和发布。
- 两个现有 GIF Markdown 文件存在且内容未被本次规范化修改。
- 所有标记为 `all` 的共享契约向量在 macOS XCTest 与 Windows NUnit 中得到同样的结果；每个受平台约束的扩展向量均在其声明的平台测试中通过。
- 输出碰撞、文件夹相对路径、覆盖保护、pngquant 无变更和失败重试在两端具有一致的可观察行为。
- macOS/Windows 平台 UI、二进制、路径适配和发布工件不被移动到 `shared/`。
- 本阶段不新增 `.gif` 导入、Gifsicle、Gifski、GIF 设置或 GIF 资源；这些内容只在后续设计阶段进入范围。
