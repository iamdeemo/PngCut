# PngCut

PngCut 是完全离线的图片压缩应用，提供独立的 macOS 与 Windows 桌面客户端。PNG、JPG 和 JPEG 均在本机处理，不上传图片，也不需要网络。

## 仓库布局

```text
macos/      SwiftUI macOS 客户端、Xcode 工程与 macOS 构建脚本
windows/    WPF Windows 客户端、.NET 解决方案与 PowerShell 发布脚本
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

详情与第三方许可证见 [macOS 说明](macos/THIRD_PARTY_NOTICES.md) 及各平台资源目录中的许可证文件。
