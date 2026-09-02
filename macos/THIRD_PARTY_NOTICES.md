# Third-party notices

引擎的固定版本、上游提交、标签和许可证标识以仓库的[共享引擎清单](../shared/contracts/v1/engine-manifest.json)为准；以下内容保留 macOS 应用资源中的许可证路径。

## pngcut

本项目（应用和项目源码）以 GNU General Public License v3（GPL v3）发布。完整文本见仓库根目录的 `LICENSE`。本项目包含 GPL v3 的 pngquant，因此整体按 GPL v3 分发。

## oxipng 10.2.0

pngcut 在本地无损 PNG 优化中捆绑 oxipng 10.2.0。oxipng 的随附许可证为 MIT License，版权声明为 `Copyright (c) 2016 Joshua Holmer`。完整许可证文本在应用资源中：`Resources/oxipng/LICENSE-oxipng`。

上游项目：<https://github.com/oxipng/oxipng>

## pngquant 3.0.3

pngcut 在本地 PNG 平衡压缩中捆绑 pngquant 3.0.3。其随附版权与许可证文件说明 pngquant 和 libimagequant 的新增与修改部分以 GPL v3 或更高版本许可；完整的上游版权与许可证文本在应用资源中：`Resources/pngquant/LICENSE-pngquant`。

上游项目：<https://github.com/kornelski/pngquant>

## MozJPEG v4.1.5

pngcut 在本地 JPG/JPEG 平衡压缩中捆绑由 MozJPEG v4.1.5 构建的静态 libjpeg 辅助程序。随附的上游许可证文件将 libjpeg-turbo 的适用许可证列为 IJG License、Modified (3-clause) BSD License 和 zlib License；完整文本在应用资源中：`Resources/mozjpeg/LICENSE-mozjpeg`。

本软件部分基于 Independent JPEG Group 的工作。

上游项目：<https://github.com/mozilla/mozjpeg>

## Gifsicle 1.96

PngCut 在本地 GIF 优化中捆绑 Gifsicle 1.96（上游标签 `v1.96`，提交 `a08e0f6686d467bb8b9e4715b1f1835f12984fb0`）的 macOS 二进制文件。其许可证标识为 `GPL-2.0-only`，完整上游许可证文本来自该标签的 `COPYING`，并随应用资源提供：`Resources/gifsicle/LICENSE-gifsicle`。

上游源码路线：<https://github.com/kohler/gifsicle/tree/v1.96>。发布 macOS 工件时，应保留该资源许可证，并遵循 `GPL-2.0-only` 对相应源代码提供的要求；`scripts/build-gifsicle.sh` 从此精确标签构建两个 macOS 架构的资源。

## Gifski 1.34.0

PngCut 在本地 PNG 序列转 GIF 中捆绑 Gifski 1.34.0（注释标签对象 `072a09c2364a07266bf05d7bfa7361bcc28381e0`，其 peeled 源提交 `1060eab4500a20f27e2fa3ab7e85473d0e921cbd`）的 macOS 二进制文件。其许可证标识为 `AGPL-3.0-or-later`，完整上游许可证文本来自该标签的 `LICENSE`，并随应用资源提供：`Resources/gifski/LICENSE-gifski`。

上游源码路线：<https://github.com/ImageOptim/gifski/tree/1.34.0>。发布 macOS 工件时，应保留该资源许可证，并遵循 `AGPL-3.0-or-later` 对相应源代码提供的要求；`scripts/build-gifski.sh` 从此精确标签以锁定依赖构建两个 macOS 架构的资源。
