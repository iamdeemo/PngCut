# PngCut

PngCut 是完全离线的图片压缩应用，提供独立的 macOS 与 Windows 桌面客户端。PNG、JPG 和 JPEG 均在本机处理，不上传图片，也不需要网络；macOS 客户端还支持 GIF 处理与 PNG 序列转 GIF。

## 仓库布局

```text
macos/      SwiftUI macOS 客户端、Xcode 工程与 macOS 构建脚本
windows/    WPF Windows 客户端、.NET 解决方案与 PowerShell 发布脚本
shared/     跨平台版本化行为契约与逻辑测试夹具说明
docs/       跨平台设计、迁移与实施文档
LICENSE     GPL v3 许可证
```

每个平台目录均可独立构建、测试与发布；不提交 `bin`、`obj`、`dist` 等可再生产物。

## macOS

要求 macOS 13+ 与 Xcode 15.2+。

```bash
cd macos
xcodebuild -project PngCut.xcodeproj -scheme PngCut -configuration Debug \
  -derivedDataPath .build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO build
open .build/DerivedData-Debug/Build/Products/Debug/pngcut.app
```

运行测试：

```bash
cd macos
xcodebuild -project PngCut.xcodeproj -scheme PngCut \
  -destination 'platform=macOS' test
```

## Windows

要求 Windows、.NET Framework 4.8 开发环境与 .NET SDK。

```powershell
Set-Location windows
dotnet test .\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x64
.\build\Build-Zip.ps1 x64
```

发布包位于 `windows/dist/PngCut-Windows-x64.zip` 或 `windows/dist/PngCut-Windows-x86.zip`。

## 压缩引擎

- PNG 无损：oxipng 10.2.0
- PNG 平衡：pngquant 3.0.3
- JPG/JPEG 平衡：MozJPEG v4.1.5
- GIF 无损：Gifsicle 1.96，使用 `gifsicle -O3`
- GIF 平衡：Gifsicle 1.96，使用 `gifsicle -O3 --lossy=200`
- PNG 序列转 GIF：Gifski 1.34.0

## GIF 与 PNG 序列

- GIF 文件按所选模式处理：无损模式使用 `gifsicle -O3`，平衡模式使用 `gifsicle -O3 --lossy=200`。
- 可将至少 10 张、连续编号且尺寸相同的 PNG 序列转换为 GIF。统一的无损/平衡模式分别映射为 Gifski `--quality 100` / `--quality 80`；这里的“无损”标签不保证生成 GIF 与原 PNG 像素完全一致。
- 帧率可选 20、25、30 FPS，或输入 1–50 FPS 的自定义值；循环可选永久循环或只播放一次。
- 输出始终保留源文件。使用默认相邻输出导入文件夹时，PngCut 会在该文件夹旁新建 `<文件夹名>_pngcut`，并在其中保留原文件夹的相对目录结构；不会把结果写回导入的源文件夹。

## JPG/JPEG 元数据

MozJPEG 会写回兼容的 APP1/APP2 元数据标记，其中包括 EXIF 与 ICC 色彩配置。COM、APP13 及其他标记可能不保留。

详情与第三方许可证见 [macOS 说明](macos/THIRD_PARTY_NOTICES.md) 及各平台资源目录中的许可证文件。
