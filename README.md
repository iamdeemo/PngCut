# pngcut

pngcut 是一个面向 macOS 的 PNG 图片压缩客户端，支持拖入 PNG 文件或文件夹后批量处理。

## 功能边界

- 仅支持 PNG；其他格式会被跳过。
- **无损**（默认）：在本机使用内置的 [oxipng](https://github.com/oxipng/oxipng) 优化 PNG，不上传图片，也不需要网络。
- **平衡**：使用 [Tinify](https://tinify.com/developers) 服务压缩。图片会上传到 Tinify；必须由用户在应用中提供自己的 API Key，并消耗该账户的压缩额度。未验证 API Key 时，该选项不可用。
- 支持将结果保存到原文件旁、指定文件夹或覆盖原文件；每次处理先写入临时文件，成功后才替换目标文件。

## 构建与运行

要求：macOS 13 或更高版本、Xcode 15.2 或更新版本。内置的 oxipng 二进制已包含 Apple Silicon 和 Intel 架构；只有重新构建 oxipng 时才需要 Rust。

在本目录执行：

```bash
xcodebuild -project FFPNG.xcodeproj -scheme FFPNG -configuration Debug \
  -derivedDataPath .build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO build
open .build/DerivedData-Debug/Build/Products/Debug/pngcut.app
```

运行单元测试：

```bash
xcodebuild -project FFPNG.xcodeproj -scheme FFPNG \
  -destination 'platform=macOS' test
```

如需更新内置 oxipng（固定版本为 v10.2.0）：

```bash
./scripts/build-oxipng.sh
```

## 制作 DMG

```bash
./scripts/create-dmg.sh
```

脚本会使用 Release 配置构建、明确关闭代码签名、生成 `dist/pngcut-<版本号>.dmg`（UDZO 格式），并执行 `hdiutil verify`。它不会签名，也不会提交 Apple 公证。

打开 DMG 后，将 `pngcut.app` 拖到同一窗口内的 `Applications` 快捷方式，再从“应用程序”文件夹启动。

## 首次打开提示

当前发布物刻意保持**未签名、未公证**，因此 macOS Gatekeeper 可能在首次打开时拦截它。下载后请在 Finder 中按住 Control 点击 `pngcut.app` 并选择“打开”，或在“系统设置 → 隐私与安全性”中选择仍要打开。仅应在确认 DMG 来源可信时这样做。

## 第三方组件

本地无损引擎 [oxipng 10.2.0](https://github.com/oxipng/oxipng) 使用 MIT 许可证。完整归属与许可文本见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，并随应用一起分发于 `Resources/oxipng/LICENSE-oxipng`。

Tinify 是可选的独立在线服务；pngcut 不内置、收集或提供 Tinify API Key。使用该服务时请同时遵守其开发者文档和服务条款。
