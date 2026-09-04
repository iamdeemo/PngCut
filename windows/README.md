# PngCut Windows 版

PngCut Windows 版是一个免安装的 .NET Framework 4.8 WPF 应用。它在本地运行，不需要网络服务或 API 密钥；压缩引擎随程序一起发布。

## 运行环境

- Windows 7 SP1 或更高版本；目标机器需要 .NET Framework 4.8。
- `x86` ZIP 适用于 32 位 Windows；`x64` ZIP 适用于 64 位 Windows。
- 发布包不包含安装程序，解压后直接运行 `PngCut.exe`。

## 本地构建

在 Windows PowerShell 中执行：

```powershell
cd G:\path\to\PngCut-packages\windows-port\windows
dotnet restore .\PngCut.sln -p:Platform=x64
dotnet build .\PngCut.sln -c Release -p:Platform=x64 --no-restore
dotnet test .\PngCut.Tests\PngCut.Tests.csproj -c Debug -p:Platform=x64
```

将 `x64` 替换为 `x86` 即可构建 32 位版本。真实引擎测试默认跳过；验证随包引擎时设置：

```powershell
$env:PNGCUT_RUN_REAL_ENGINES = '1'
dotnet test .\PngCut.Tests\PngCut.Tests.csproj -c Debug -p:Platform=x64 --filter FullyQualifiedName~RealEngineIntegrationTests
```

## 引擎来源与可复核信息

各引擎的固定版本、上游提交、标签和许可证标识以仓库的[共享引擎清单](../shared/contracts/v1/engine-manifest.json)为准；Windows ZIP 仍保留本平台的二进制哈希和许可证目录校验。

发布前可使用 `Get-FileHash -Algorithm SHA256` 复核随仓库提交的 Windows 二进制。当前构建资源的哈希如下：

```text
x64/mozjpeg-helper.exe  C6C0A41F007A388815D9A87FE2F03D9D4A9A705257EC0AEB71CFB2ACA700E53C
x64/oxipng.exe          40872EA91D461520FFC79EFF791D9D9503CB445695933F58A826D54681D6292A
x64/pngquant.exe        8C4F0C41F3F97CD1D3F476C75F73268E76C6DA76DBFE35187776D57C8B7E36A
x86/mozjpeg-helper.exe  CED829BCD1AA8E70DC167F45D397FA93ACB56BF7799A85F38276B6F84E2A0AD5
x86/oxipng.exe          2A3EFDE82B0E41AB4291616E21C780912B09DC660FB246EF1061AE32EE06F44E
x86/pngquant.exe        FB6D09E7055E2F91D3CE5EB065027ECD40188BB8063D6D51348BD67EB49E7C9D
```

各引擎的许可证和发布注意事项位于 `Resources\licenses`。其中 pngquant 遵循 GPL v3，发布 ZIP 时必须同时提供对应许可证及源码获取/构建信息。

## 生成免安装 ZIP

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Zip.ps1 x86
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Zip.ps1 x64
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Test-ReleaseLayout.ps1 -ZipPath .\dist\PngCut-Windows-x86.zip
powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Test-ReleaseLayout.ps1 -ZipPath .\dist\PngCut-Windows-x64.zip
```

ZIP 只包含匹配架构的三个引擎、应用依赖、许可证和本说明，不包含安装程序、源图片、用户设置或 API 密钥。
