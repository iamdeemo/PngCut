# PngCut GitHub 同步与项目命名迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 保留 `iamdeemo/FFPNG` 的既有 Git 历史，将当前 macOS 与 Windows 源码同步到 GitHub，并将产品工程标识迁移为 `PngCut`。

**Architecture:** 以 `G:/codex/PngCut-packages/FFPNG` 作为唯一 Git 根目录，先把工作树附着到远端 `main`，再以普通提交记录本地差异。macOS 与 Windows 均使用顶层自包含目录：`macos/` 和 `windows/`；根目录仅保留跨平台 README、许可证和共享文档。两个平台目录都排除可再生的 `bin/`、`obj/`、`dist/` 与本地工具输出。

**Tech Stack:** Git/GitHub、Xcode SwiftUI、.NET Framework 4.8 WPF、PowerShell、NUnit。

---

### Task 1: 将工作树接入远端历史

**Files:**

- Modify: `G:/codex/PngCut-packages/FFPNG/.gitignore`
- Verify: `G:/codex/PngCut-packages/FFPNG/.git`

- [ ] **Step 1: 初始化并获取远端历史，不覆盖工作树**

```powershell
git -C G:/codex/PngCut-packages/FFPNG init -b main
git -C G:/codex/PngCut-packages/FFPNG remote add origin https://github.com/iamdeemo/FFPNG.git
git -C G:/codex/PngCut-packages/FFPNG fetch origin main
git -C G:/codex/PngCut-packages/FFPNG reset --mixed origin/main
```

Expected: `git status --short` 仅显示本地差异，工作树内容不被删除。

- [ ] **Step 2: 排除 Windows 生成物**

```gitignore
# Windows local build products
windows/**/bin/
windows/**/obj/
windows/dist/
windows/.vs/
```

- [ ] **Step 3: 验证改动范围并提交 macOS 已有改动**

```powershell
git -C G:/codex/PngCut-packages/FFPNG diff --check
git -C G:/codex/PngCut-packages/FFPNG add -A
git -C G:/codex/PngCut-packages/FFPNG commit -m "feat: make macOS compression fully offline"
```

Expected: 无空白错误，且产生一个以 `origin/main` 为父提交的本地提交。

### Task 2: 建立平台目录并纳入 Windows 源码

**Files:**

- Create: `G:/codex/PngCut-packages/FFPNG/macos/`
- Create: `G:/codex/PngCut-packages/FFPNG/windows/`
- Test: `G:/codex/PngCut-packages/FFPNG/windows/PngCut.Tests/PngCut.Tests.csproj`

- [ ] **Step 1: 将现有 macOS 工程迁入 macos/，复制 Windows 源码并跳过生成目录**

```powershell
git -C G:/codex/PngCut-packages/FFPNG mv FFPNG FFPNG.xcodeproj FFPNGTests FFPNGUITests scripts THIRD_PARTY_NOTICES.md macos
robocopy G:/codex/PngCut-packages/windows-port/windows G:/codex/PngCut-packages/FFPNG/windows /E /XD bin obj dist .vs stage-x86 stage-x64
if ($LASTEXITCODE -gt 7) { exit $LASTEXITCODE }
```

Expected: `macos/` 包含 Xcode 工程，`windows/` 包含 `PngCut.sln`、`src/`、`PngCut.Tests/`、`build/`；两个目录均不含 `bin/`、`obj/`、`dist/`。

- [ ] **Step 2: 验证两个架构并提交**

```powershell
dotnet test G:/codex/PngCut-packages/FFPNG/windows/PngCut.Tests/PngCut.Tests.csproj -c Release -p:Platform=x64
dotnet test G:/codex/PngCut-packages/FFPNG/windows/PngCut.Tests/PngCut.Tests.csproj -c Release -p:Platform=x86
git -C G:/codex/PngCut-packages/FFPNG add windows .gitignore
git -C G:/codex/PngCut-packages/FFPNG commit -m "feat: add Windows desktop port"
```

Expected: 两个架构常规测试通过，提交不含发布包和中间产物。

### Task 3: 统一公开工程标识为 PngCut

**Files:**

- Modify: `G:/codex/PngCut-packages/FFPNG/FFPNG.xcodeproj/project.pbxproj`
- Modify: `G:/codex/PngCut-packages/FFPNG/FFPNG.xcodeproj/xcshareddata/xcschemes/FFPNG.xcscheme`
- Modify: `G:/codex/PngCut-packages/FFPNG/FFPNG/App/FFPNGApp.swift`
- Modify: `G:/codex/PngCut-packages/FFPNG/FFPNGTests/FFPNGTests.swift`
- Modify: `G:/codex/PngCut-packages/FFPNG/FFPNGUITests/FFPNGUITests.swift`
- Modify: `G:/codex/PngCut-packages/FFPNG/README.md`

- [ ] **Step 1: 写入构建检查并确认重命名前失败**

```bash
xcodebuild -project PngCut.xcodeproj -scheme PngCut -configuration Debug \
  -derivedDataPath .build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO build
```

Expected before rename: FAIL，因为 `PngCut.xcodeproj` 与 scheme 尚不存在。

- [ ] **Step 2: 使用 git mv 重命名工程、模块和测试目录**

```powershell
git -C G:/codex/PngCut-packages/FFPNG mv FFPNG.xcodeproj PngCut.xcodeproj
git -C G:/codex/PngCut-packages/FFPNG mv FFPNG PngCut
git -C G:/codex/PngCut-packages/FFPNG mv FFPNGTests PngCutTests
git -C G:/codex/PngCut-packages/FFPNG mv FFPNGUITests PngCutUITests
```

Then replace target, scheme, test-host and module references `FFPNG` with `PngCut` in the renamed project files; retain lowercase executable product name `pngcut` for macOS compatibility.

- [ ] **Step 3: 验证并提交命名迁移**

```bash
rg -n "FFPNG" PngCut.xcodeproj PngCut PngCutTests PngCutUITests README.md
xcodebuild -project PngCut.xcodeproj -scheme PngCut -configuration Debug \
  -derivedDataPath .build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO build
```

```powershell
git -C G:/codex/PngCut-packages/FFPNG add -A
git -C G:/codex/PngCut-packages/FFPNG commit -m "refactor: rename project to PngCut"
```

Expected: 仅允许历史链接保留 `FFPNG`；macOS 环境可构建 `pngcut.app`。

### Task 4: 推送与后续同步

**Files:**

- Verify: `G:/codex/PngCut-packages/FFPNG/.git/config`

- [ ] **Step 1: 推送前验证**

```powershell
git -C G:/codex/PngCut-packages/FFPNG log --oneline origin/main..HEAD
git -C G:/codex/PngCut-packages/FFPNG status --short
git -C G:/codex/PngCut-packages/FFPNG diff --check origin/main...HEAD
```

- [ ] **Step 2: 推送 main**

```powershell
git -C G:/codex/PngCut-packages/FFPNG push -u origin main
```

Expected: GitHub `main` 指向新提交；若认证失败，使用 Git Credential Manager 登录后重试，不写入明文令牌。

- [ ] **Step 3: 验证后续同步配置**

```powershell
git -C G:/codex/PngCut-packages/FFPNG status --short
git -C G:/codex/PngCut-packages/FFPNG remote -v
```

Expected: 工作树干净，`origin` 为 GitHub 仓库。若需将 GitHub 仓库显示名也改为 `PngCut`，需在 GitHub 设置中重命名，或安装并登录 GitHub CLI 后执行仓库重命名。
