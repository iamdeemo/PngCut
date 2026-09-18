# PngCut

PngCut 是完全离线的图片压缩应用，提供独立的 macOS 与 Windows 桌面客户端。PNG、JPG 和 JPEG 均在本机处理，不上传图片，也不需要网络；macOS 客户端还支持 GIF 处理与 PNG 序列转 GIF。

## 下载与安装

### macOS 1.0.2

适用于 macOS 13 及以上，支持 Intel 与 Apple 芯片。安装运行不需要 Xcode。

- [下载 PngCut-1.0.2.dmg](https://github.com/iamdeemo/PngCut/releases/download/v1.0.2/PngCut-1.0.2.dmg)
- [查看发布说明](https://github.com/iamdeemo/PngCut/releases/tag/v1.0.2) · [下载中文更新说明](https://github.com/iamdeemo/PngCut/releases/download/v1.0.2/PngCut-1.0.2-Release-Notes.md) · [下载 SHA256 校验文件](https://github.com/iamdeemo/PngCut/releases/download/v1.0.2/PngCut-1.0.2-SHA256SUMS.txt)

打开 DMG，将 `PngCut.app` 拖入 `Applications`，再从应用程序目录启动。更新时请先退出旧版，再替换应用；1.0.2 沿用原有应用标识与设置。

当前安装包未进行 Developer ID 签名及 Apple 公证，首次启动可能受到 macOS 安全机制阻止。请仅使用本项目发布页的安装包。

如需校验，将 DMG、中文更新说明与 SHA256 校验文件放在同一目录，在该目录运行：

```bash
shasum -a 256 -c PngCut-1.0.2-SHA256SUMS.txt
```

### Windows

Windows 安装包仍在 [1.0.0 发布页](https://github.com/iamdeemo/PngCut/releases/tag/v1.0.0)，1.0.2 的客户端更新仅适用于 macOS。

- [64 位 Windows 下载](https://github.com/iamdeemo/PngCut/releases/download/v1.0.0/PngCut-Windows-x64.zip)
- [32 位 Windows 下载](https://github.com/iamdeemo/PngCut/releases/download/v1.0.0/PngCut-Windows-x86.zip)

Windows 7 SP1 或更高版本，需要 .NET Framework 4.8。解压后运行 `PngCut.exe`，无需安装程序。详见 [Windows 说明](windows/README.md)。

## macOS 使用方法

1. 在底部选择“无损”或“平衡”模式。
2. 将图片或文件夹拖入窗口，也可点击“选择文件”批量添加。
3. 导入后自动处理，在任务列表查看进度、处理结果与文件大小；失败任务可重试。
4. 点击右下角设置按钮配置保存位置或 PNG 序列转 GIF；文件夹按钮用于打开输出文件夹。

PNG 与 GIF 按所选模式压缩；JPG/JPEG 始终使用 MozJPEG 平衡压缩，不提供 JPEG 无损压缩。

### 保存位置

- **原文件旁边（默认）**：单张图片输出为 `<原文件名>_pngcut.<扩展名>`；导入文件夹时，在该文件夹旁创建 `<文件夹名>_pngcut`，保留相对目录结构，不改动源图片。同名输出会自动增加编号。
- **指定输出文件夹**：可点击“选择…”浏览文件夹，也可手动填写绝对路径或 `~/` 路径，按回车或离开输入框时保存。支持中文及带空格的路径；文件夹必须已存在且可写入。无效路径会显示提示，不替换先前保存的有效路径。
- **覆盖原文件**：压缩结果会替换源图片，使用前请自行备份。PNG 序列转 GIF 仍生成单独的 GIF，不覆盖源 PNG。

### 1.0.2 更新摘要

- 标题统一为 PngCut，缩小标题栏；首页提示简化为“拖入图片或文件夹”，移除图标底色，调整虚线框范围。
- 设置采用紧凑分组布局，缩小模式选项间距，增加手动填写输出路径。
- 统一弹窗按钮风格，完善页面切换、控件反馈及任务状态动效，支持系统“减少动态效果”设置。

完整更新内容与验证范围见 [更新说明](CHANGELOG.md)。

## 仓库布局

```text
macos/      SwiftUI macOS 客户端、Xcode 工程与 macOS 构建脚本
windows/    WPF Windows 客户端、.NET 解决方案与 PowerShell 发布脚本
shared/     跨平台版本化行为契约与逻辑测试夹具说明
docs/       跨平台设计、迁移与实施文档
LICENSE     GPL v3 许可证
```

每个平台目录均可独立构建、测试与发布；不提交 `bin`、`obj`、`dist` 等可再生产物。

## 开发与构建

### macOS

需要 macOS 13+ 与 Xcode 15.2+。以下命令均在仓库根目录运行。

构建并启动 Debug 应用：

```bash
xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -configuration Debug \
  -derivedDataPath macos/.build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO build
open macos/.build/DerivedData-Debug/Build/Products/Debug/pngcut.app
```

打包 DMG：

```bash
bash macos/scripts/create-dmg.sh
```

安装包输出至 `macos/dist/PngCut-1.0.2.dmg`。脚本会执行 Release 构建，并检查 DMG 完整性、应用通用架构、内置压缩工具与许可证；不执行 Developer ID 签名或 Apple 公证。

运行单元与模型测试：

```bash
xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath macos/.build/DerivedData-Debug \
  CODE_SIGNING_ALLOWED=NO test -only-testing:PngCutTests
```

去掉 `-only-testing:PngCutTests` 可运行包含界面测试的完整测试集。界面测试需要 macOS 允许 UI 自动化；测试使用独立偏好设置，不更改日常使用的应用设置。

### Windows

在 Windows 上构建，需要 .NET Framework 4.8 开发环境与 .NET SDK。在仓库根目录打开 PowerShell：

```powershell
Set-Location windows
dotnet test .\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x64
.\build\Build-Zip.ps1 x64
```

发布包位于 `windows/dist/PngCut-Windows-x64.zip` 或 `windows/dist/PngCut-Windows-x86.zip`。

详细构建与发布校验步骤见 [Windows 说明](windows/README.md)；跨平台行为约定与测试夹具见 [共享契约](shared/contracts/v1/behavior.json) 和 [夹具说明](shared/fixtures/README.md)。

## 压缩引擎

- PNG 无损：oxipng 10.2.0
- PNG 平衡：pngquant 3.0.3
- JPG/JPEG 平衡：MozJPEG v4.1.5
- GIF 无损：Gifsicle 1.96，使用 `gifsicle -O3`
- GIF 平衡：Gifsicle 1.96，使用 `gifsicle -O3 --lossy=200`
- PNG 序列转 GIF：Gifski 1.34.0

## GIF 与 PNG 序列

- GIF 文件按所选模式处理：无损模式使用 `gifsicle -O3`，平衡模式使用 `gifsicle -O3 --lossy=200`。
- PNG 序列需位于同一目录、具有相同文件名前缀和末尾连续编号，至少 10 张，且尺寸相同（例如 `frame001.png` 至 `frame010.png`）。发现序列时可选择转 GIF，也可在设置中启用“PNG 序列转 GIF”。统一的无损/平衡模式分别映射为 Gifski `--quality 100` / `--quality 80`；这里的“无损”标签不保证生成 GIF 与原 PNG 像素完全一致。
- 帧率可选 20、25、30 FPS，或输入 1–50 FPS 的自定义值；循环可选永久循环或只播放一次。
- 生成 GIF 始终保留源 PNG，同名 GIF 会自动增加编号。默认相邻输出导入文件夹时，生成的 GIF 位于该文件夹旁的 `<文件夹名>_pngcut` 中，保留相对目录结构。

## JPG/JPEG 元数据

MozJPEG 会写回兼容的 APP1/APP2 元数据标记，其中包括 EXIF 与 ICC 色彩配置。COM、APP13 及其他标记可能不保留。

详情与第三方许可证见 [macOS 说明](macos/THIRD_PARTY_NOTICES.md) 及各平台资源目录中的许可证文件。

## 许可证

PngCut 采用 [GPL v3](LICENSE)。随应用分发的第三方压缩引擎遵循各自许可证，发布包包含对应许可证文件。
